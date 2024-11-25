# Hopefully will replace the REPL class in core at some point
use nqp;
use Commands:ver<0.0.2+>:auth<zef:lizmat>;
use Prompt:ver<0.0.5+>:auth<zef:lizmat>;

#- constants and prologue ------------------------------------------------------
my enum Status <OK MORE-INPUT CONTROL>;

# Is word long enough?
sub long-enough($_) { .chars > 1 ?? $_ !! Empty }

# Is a word ok to be included in completions
sub ok-for-completion($_) {
    .contains(/ <.lower> /)
      ?? .starts-with('&')
        ?? .contains("fix:" | "mod:")
          ?? Empty            # don't bother with operators and traits
          !! long-enough(.substr(1))
        !! .contains(/ \W /)
          ?? Empty            # don't bother with non-sub specials
          !! long-enough($_)
      !! Empty                # don't bother will all uppercase
}

# Set core completions
my constant @core-completions = CORE::.keys.map(&ok-for-completion).sort;

PROCESS::<$SCHEDULER>.uncaught_handler =  -> $exception {
    note "Uncaught exception on thread $*THREAD.id():\n"
      ~ $exception.gist.indent(4);
}

#- standard completions --------------------------------------------------------

my $uniname-words = try "use uniname-words; &uniname-words".EVAL;
my sub uniname-words(|c) is export {
    $uniname-words ?? $uniname-words(|c) !! Nil
}

# Set up standard completions
my sub standard-completions($line, $pos is copy = $line.chars) is export {

    # Check for \c[word ... ] completions
    with $uniname-words && $line.rindex('\\c[') -> $start is copy {
        $start += 3;
        without $line.index(']', $start) {
            if $line.chars > $start {
                with $uniname-words($line.substr($start).lc) {
                    my $prefix := $line.substr(0, $start);
                    .map({ qq/$prefix$_.uniname()]/ }).sort
                }
            }
        }
    }

    # Check for \^123, \_123, \word completions
    orwith $line.rindex('\\') -> $start is copy {
        without $line.index(' ', $start) {
            if $line.chars > $start {
                my $word   := $line.substr($start+1).lc;
                my $prefix := $line.substr(0, $start);
                if $word.starts-with('^')
                  && try $word.substr(1).Int -> $number {
                    ($prefix ~ $number.Str(:superscript),)
                }
                elsif $word.starts-with('_')
                  && try $word.substr(1).Int -> $number {
                    ($prefix ~ $number.Str(:subscript),)
                }
                orwith $uniname-words
                  && $uniname-words($line.substr($start+1).lc) {
                    .sort(*.uniname).map({ qq/$prefix$_.chr()/ })
                }
            }
        }
    }

    # Check for word! completions
    elsif $pos && $line.substr-eq('!', --$pos) {
        with $line.rindex(' ', $pos) -> $index is copy {
            my $prefix := $line.substr(0, ++$index);
            my $target := $line.substr($index, $pos - $index);
            ($prefix ~ $target.uc,
             $prefix ~ $target.lc,
             $prefix ~ $target.tclc
            )
        }
        else {
            my $target := $line.substr(0,$pos);
            ($target.uc, $target.lc, $target.tclc)
        }
    }
}

#- REPL ------------------------------------------------------------------------
role REPL {

    # The low level compiler to be used
    has Mu $.compiler = "Raku";

    # When values are shown, use this method on the object
    has Str $.output-method = %*ENV<RAKU_REPL_OUTPUT_METHOD> // "gist";

    # The values that were recorded in this session, available inside
    # the REPL as $*0, $*1, etc.
    has Mu @.values;

    # The prompt logic being used
    has Mu $.prompt handles <
      additional-completions add-history completions editor-name read
      readline load-history save-history supports-completions
    >;

    # Output handles
    has $.out;
    has $.err;
    has $.val;

    # The current NQP context that has all of the definitions that were
    # made in this session
    has Mu $.context is built(:bind) = nqp::null;

    # Whether it is allowed to have code evalled stretching over
    # multiple lines
    has Bool $.multi-line-ok = !%*ENV<RAKUDO_DISABLE_MULTILINE>;

    # On Windows some things need to be different, this allows an easy check
    has Bool $.is-win is built(:bind) = $*DISTRO.is-win;

    # Flag whether the extended header should be shown
    has Bool $!header is built = True;

    # Return state from evaluation
    has Status $!state = OK;

    # Any exception that should be reported
    has Mu $.exception is rw is built(False);

    # Number of time control-c was seen
    has int $!ctrl-c;

    method new(Mu :$context is copy, :$no-context) {
        $context := nqp::decont($context);
        $context := nqp::ctxcaller(nqp::ctx)
          unless nqp::isconcrete($context);

        self.bless(:$context, |%_)
    }

    method TWEAK(:$editor, :@additional-completions) {
        $!compiler := nqp::getcomp(nqp::decont($!compiler))
          if nqp::istype($!compiler,Str);

        $!context := nqp::decont($!context);

        if $*VM.name eq 'moar' {
            signal(SIGINT).tap: {
                if $!ctrl-c++ {
                    self.teardown;
                    exit;
                }
                self.err.say: "Pressed CTRL-c, press CTRL-c again to exit";
                print self.interactive_prompt;
            }
        }

        # Set up standard additional completions if none so far
        @additional-completions = &standard-completions
          unless @additional-completions;

        # Make a prompt object if we don't have one yet
        $!prompt := Prompt.new(
          $editor,
          :@additional-completions
        ) without $!prompt;

        # Make sure we have a history file
        $!prompt.history(self.rakudo-history(:create))
          without $!prompt.history;
    }

    method teardown() { self.save-history }
    method val() { $!val // $*OUT }
    method out() { $!out // $*OUT }
    method err() { $!err // $*ERR }

    method sink() { .run with self }

    method interactive_prompt() { "[@!values.elems()] > " }

    method rakudo-history(:$create) {
        my $path := do if %*ENV<RAKUDO_HIST> -> $history {
            $history.IO
        }
        else {
            ($*HOME || $*TMPDIR).add('.raku/rakudo-history')
        }

        if $create && !$path.e {
            CATCH {
                note "Could not set up history file '$path':\n  $_.message()";
                .resume;
            }
            $path.spurt;
        }

        $path
    }

    method repl-loop(|c) { self.run(|c) }

    method run(:$no-exit) {
        if $!header {
            self.val.say: $!compiler.version_string(
              :shorten-versions,
              :no-unicode($!is-win)
            ) ~ "\n";
            $!header = False;
        }

        say $no-exit
          ?? "Type 'exit' to leave"
          !! $!is-win
            ?? "To exit type 'exit' or '^Z'"
            !! "To exit type 'exit' or '^D'";

        my str $prompt;
        my str $code;
        sub reset(--> Nil) {
            $code   = '';
            $prompt = self.interactive_prompt;
        }
        reset;

        my $commands := Commands.new(
          :$!out, :$!err,
          default => {

              # Evaluate the code
              my int $out-tell = $*OUT.tell;
              my int $err-tell = $*ERR.tell;
              my $value := self.eval($*INPUT, |%_);

              # Handle the special cases
              if $!state == MORE-INPUT {
                  $prompt = '* ';
                  next;
              }
              elsif $!state == CONTROL {
                  say "Control flow commands not allowed in toplevel";
                  reset;
                  next;
              }

              # Print an exception if one had occured
              if $!exception.DEFINITE {
                  note $!exception.message.chomp;
                  $!exception = Nil;
              }

              # Print the result if:
              # - there wasn't some other output
              # - the result is an *unhandled* Failure
              elsif $*OUT.tell == $out-tell && $*ERR.tell == $err-tell
                or nqp::istype($value,Failure) && !$value.handled {
                  my $method := $!output-method;
                  CATCH {
                      note ."$method"();
                      .resume
                  }

                  self.val.say: (nqp::can($value,$method)
                    ?? $value."$method"()
                    !! "(low-level object `$value.^name()`)"
                  );

                  @!values.push: $value;
              }
          },
          commands => (
            exit   => { last },
            quit   => "exit",
            editor => { say "Using the $!prompt.editor-name() editor" },
            help   => { say "Available commands: $commands.primaries.skip()" },
            output => {
                if .[1] -> $method {
                    $!output-method := $method;
                    say "Output method is now set to '$method'";
                }
                else {
                    say "Current output method is '$!output-method'";
                }
            },
            ""     => { next },
          ),
        );

        if self.supports-completions && !self.completions {
            self.completions(@core-completions, self.context-completions);
        }

        # Make sure we can reference previous values from within the
        # REPL as $*0, $*1 etc
        my @*_ := @!values;

        loop {
            # Why doesn't the catch-default in eval catch all?
            CATCH {
                default { say $_; reset }
            }

            # Fetch the code
            last without my $command := $!prompt.readline($prompt);

            $!ctrl-c = 0;
            $code    = $code ~ $command ~ "\n";

            $commands.process($code.chomp);
            reset;
        }

        self.teardown;
    }

    method eval($code) {
        CATCH {
            when X::Syntax::Missing | X::Comp::FailGoal {
                if $!multi-line-ok && .pos == $code.chars {
                    $!state = MORE-INPUT;
                    return Nil;
                }
                else {
                    .throw
                }
            }

            when X::ControlFlow::Return {
                $!state = CONTROL;
                return Nil;
            }

            default {
                $!exception = $_;
                return Nil;
            }
        }

        CONTROL {
            when CX::Emit | CX::Take {
                .rethrow;
            }
            when CX::Warn {
                .gist.say;
                .resume;
            }
            default {
                $!state = CONTROL;
                return Nil;
            }
        }

        # Performe the actual evaluation magic
        my $*CTXSAVE  := self;
        my $*MAIN_CTX := $!context;
        my $value := do {
            $!compiler.eval(
              $code.subst(/ '$*' \d+ /, { '@*_[' ~ $/.substr(2) ~ ']' }, :g),
              :outer_ctx($!context),
              :interactive(1),
              |%_
            );
        }

        # Save the context state for the next evaluation
        $!context := $*MAIN_CTX;

        $value
    }

    # This appears to be a magic method that is called somewhere inside
    # the compiler.  The semantics of $*MAIN_CTX and $*CTXSAVE appear
    # to be needed to get a persistency with regards to scope between
    # lines entered in the REPL.
    method ctxsave(--> Nil) {
        $*MAIN_CTX := nqp::ctxcaller(nqp::ctx);
        $*CTXSAVE  := 0;
    }

    # Provide completions for the current context
    method context-completions() {
        my $iterator := nqp::iterator(nqp::ctxlexpad($!context));

        my $buffer := nqp::create(IterationBuffer);
        nqp::while(
          $iterator,
          nqp::push($buffer, nqp::iterkey_s(nqp::shift($iterator)))
        );

        my $PACKAGE := $!compiler.eval('$?PACKAGE', :outer_ctx($!context));
        $PACKAGE.WHO.keys.map(&ok-for-completion).iterator.push-all($buffer);

        $buffer.Slip
    }
}

#- subroutines -----------------------------------------------------------------
my sub repl(*%_) is export {
    my $context := nqp::ctxcaller(nqp::ctx);
    REPL.new(:no-exit, :$context, :!header, |%_)
}

my sub context(--> Mu) is export {
    nqp::ctxcaller(nqp::ctx)
}

# vim: expandtab shiftwidth=4
