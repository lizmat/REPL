# Hopefully will replace the REPL class in core at some point
use nqp;
use Commands:ver<0.0.6+>:auth<zef:lizmat>;
use Prompt:ver<0.0.9+>:auth<zef:lizmat>;
use Prompt::Expand:ver<0.0.3+>:auth<zef:lizmat>;

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

# Just a visual divider
sub line() { say "-" x 70 }

# Set core completions
my constant @core-completions = CORE::.keys.map(&ok-for-completion).sort;

PROCESS::<$SCHEDULER>.uncaught_handler =  -> $exception {
    note "Uncaught exception on thread $*THREAD.id():\n"
      ~ $exception.gist.indent(4);
}

#- standard completions --------------------------------------------------------

# from String::Utils:ver<0.0.31+>:auth<zef:lizmat>
my sub word-at(str $string, int $cursor) {

    # something to look at
    if $cursor >= 0 && nqp::chars($string) -> int $length {
        my int $last;
        my int $pos;
        my int $index;
        nqp::while(
          $last < $length && ($pos = nqp::findcclass(
            nqp::const::CCLASS_WHITESPACE,
            $string,
            $last,
            $length - $last
          )) < $cursor,
          nqp::stmts(
            nqp::if($pos > $last, ++$index),
            ($last  = $pos + 1)
          )
        );
        $last >= $length || $pos == $last
          ?? Empty
          !! ($last, $pos - $last, $index)
    }

    # nothing to look at
    else {
        Empty
    }
}

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

#- primary handlers ------------------------------------------------------------

# The active REPL class and Commands object
my $app;
my $commands;
my $helper;

my sub completions($) {
    say expand ":bold:About TAB completions:unbold:";
    line;
    print expand q:to/COMPLETIONS/;
The TAB key has a special function in the REPL.  When pressed,
the REPL tries to elucidate what you as a user want to expand.

If the line starts with "=", then it will look in the list of
available REPL commands, and show the first that matched.
Pressing TAB again will show the second, and so on until the
list is exhausted, at which point it will start from the
beginning again.  At any point you can add additional characters
(or remove them) and press TAB again to create a new list of
alternatives.

For example, pressing "=", "e", "TAB" will show "=editor".
Pressing TAB again, will show "=exit".  And pressing TAB once
again, will show "=e" again.

If the line does :bold:not:unbold: start with "=", then TAB completions will
attempt to complete to Raku core features.  For instance,
entering "Da", and then pressing TAB repeatedly will cycle
through "Date", "DateTime", "Dateish", all core Raku features.

Finally, some special REPL completions will change the presentation
of the string immediately preceding it.  They are:

\^123  - change integer value to superscript: ¹²³ 
\_123  - change integer value to subscript: ₁₂₃
fOo!   - cycle through FOO, foo, Foo (upper, lower, titlecase)
COMPLETIONS
    line;
}

my sub editor($) {
    say "Using the $app.prompt.editor-name() editor."
}

my sub help($_) {
    if .skip.join(" ") -> $deeper {
        $helper.process($deeper)
    }
    else {
        say "Available REPL commands:";
        line;
        say $commands.primaries().join(" ").naive-word-wrapper;
        say "\nMore in-depth help available with '=help <command>'";
    }
}

my sub introduction($) {
    say expand ":bold:Introduction to the Read Evaluate Print Loop:unbold:";
    line;
    print expand qq:to/INTRODUCTION/;
The Read Evaluate Print Loop provides an interactive way to enter
Raku Programming Language commands and see the results of their
execution immediately.

If the code entered does not cause any output (whether that be on
STDOUT or STDERR), then the result of the code will be saved and
an internal index will be incremented (which is usually shown as
"[0]" in the prompt).  Previously saved values can be accessed by
the "\$*0", "\$*1", etc.

If the code entered was deemed to be incomplete, the symbol in the
prompt changes (from ':bold:$app.symbols()[0]:unbold:' to ':bold:$app.symbols()[1]:unbold:') to indicate that you need to
enter more code before a result can be calculated.

Apart from being able to enter source code, one can also enter a
number of REPL specific commands, which all start with a "=" symbol.

The "=" symbol was chosen because it has a special meaning in the
Raku Programming Language when used at the beginning of a line: it
then indicates so-called RakuDoc: external (user) documentation
embedded in the source code.  Since one will most likely not be
documenting source code in a REPL, it was thought to be a good
choice for use as a REPL command escape.

The available REPL commands are:
INTRODUCTION

    say "  '$_'" for $commands.primaries.grep({$_});

    print expand q:to/INTRODUCTION/;

If you need more help on a REPL command, you can do '=help =command'.

:bold:Note::unbold: you can always press TAB for so-called "TAB completions".
This allows you to get to e.g. get to '=help =editor' by entering
"=", "h", TAB, "=", "e", TAB.  See "=completions" for more info
on TAB completions.
INTRODUCTION
    line;
}

my sub output($_) {
    if .[1] -> $method {
        $app.output-method = $method;
        say "Output method is now set to '$method'.";
    }
    else {
        say "Current output method is '$app.output-method()'.";
    }
}

my constant %help = do {
    my @help =

  completions => q:to/COMPLETIONS/,
Provides information about TAB completions.
COMPLETIONS

  editor => q:to/EDITOR/,
Show the name of the underlying editor that is being used.  This is
purely informational.  Note that only Linenoise and LineEditor allow
tab-completions.
EDITOR

  exit => q:to/EXIT/,
Exit and save any history.
EXIT

  help => q:to/HELP/,
Show available commands if used without additional argument.  If a
command is specified as an additional argument, show any in-depth
information about that command.
HELP

  introduction => q:to/INTRODUCTION/,
Provides an introduction to the ReadEvaluatePrintLoop.
INTRODUCTION

  output => q:to/OUTPUT/,
Show or set the expression value output method (e.g. "Str" or
"gist").
OUTPUT

  quit => q:to/QUIT/,
Exit and save any history.
QUIT
    ;

    @help.Slip, @help.map({"=$_.key()" => .value}).Slip
}

my sub no-extended($_) {
    say "No extended help available for: $_"
}

my sub moreinfo(Str:D $command, Str:D $text) {
    say "More information about: $command";
    line;
    say $text.chomp
}

#- additional completions ------------------------------------------------------

sub additional-completions($line, $pos) {

    my ($start, $chars, $index) = word-at($line, $pos);
    if $start.defined {
        my $before := $line.substr(0,$start);
        my $target := $line.substr($start, $chars).lc;
        my $after  := $line.substr($start + $chars);
        $after := " " unless $after;

        # primary command
        if $index == 0 {
            $commands.primaries.map({
                $before ~ $_ ~ $after if .starts-with($target)
            }).List
        }

        # secondary command
        elsif $index == 1 {
            my @words    = $line.words;
            my $action  := $commands.resolve-command(@words.head);
            my sub grepper($_) { $_ if .contains($target, :i, :m) }
            my @targets;

            if $action eq '=help' {
                @targets = $helper.primaries.map(&grepper)
            }

            @targets.map({ $before ~ $_ ~ $after }).sort(*.fc).List
        }
    }
}

#- REPL ------------------------------------------------------------------------
role REPL:ver<0.0.13>:auth<zef:lizmat> {

    # The low level compiler to be used
    has Mu $.compiler = "Raku";

    # When values are shown, use this method on the object
    has Str $.output-method is rw = %*ENV<RAKU_REPL_OUTPUT_METHOD> // "gist";

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

    # Visible prompt handling
    has Str $.the-prompt = %*ENV<RAKUDO_REPL_PROMPT> // '[:index:] :symbol: ';
    has Str @.symbols;

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

        $!the-prompt ~= " :symbol: "
          unless $!the-prompt.contains(":symbol:");
        @!symbols = (%*ENV<RAKUDO_REPL_SYMBOLS> // ">,*").split(",")
          unless @!symbols;

        if $*VM.name eq 'moar' {
            signal(SIGINT).tap: {
                if $!ctrl-c++ {
                    self.teardown;
                    exit;
                }
                self.err.say: "Pressed CTRL-c, press CTRL-c again to exit";
                print self.the-prompt;
            }
        }

        # Set up standard additional completions if none so far
        @additional-completions =
          &standard-completions,
          &additional-completions
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

    method the-prompt() {
        expand($!the-prompt,
          :index(@!values.elems),
          :symbol(@!symbols[$!state] // "$!state?")
        )
    }

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
          ?? "Type '=quit' to leave"
          !! $!is-win
            ?? "To exit type '=quit' or '^Z'"
            !! "To exit type '=quit' or '^D'";

        my str $prompt;
        my str $code;
        sub reset(--> Nil) { $code   = '' }
        reset;

        $app      := self;
        $commands := Commands.new(
          :$!out, :$!err,
          default => {

              # Evaluate the code
              my int $out-tell = $*OUT.tell;
              my int $err-tell = $*ERR.tell;
              my $value := self.eval($*INPUT, |%_);

              # Handle the special cases
              if $!state == MORE-INPUT {
                  next;
              }
              elsif $!state == CONTROL {
                  say "Control flow commands not allowed in toplevel";
                  $!state = OK;
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
            "=exit"   => { last },
            "=quit"   => { last },
            ""        => { next },
            (&completions, &editor, &help, &introduction, &output).map({
                "=$_.name()" => $_
            }).Slip
          ),
        );

        $helper = $commands.extended-help-from-hash(
          %help, :default(&no-extended), :handler(&moreinfo)
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
            my $command := $!prompt.readline(self.the-prompt);
            last without $command;

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

            when X::Syntax::InfixInTermPosition {
                if .infix eq "=" && $code.starts-with("=") {
                    say "Unknown REPL command: $code.words.head()";
                    say "Enter '=help' for a list of available REPL commands.";
                }
                else {
                    $!exception = $_;
                }
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
        $!state    = OK;
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
