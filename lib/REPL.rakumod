# Hopefully will replace the REPL class in core at some point
use nqp;

#- constants and prologue ------------------------------------------------------
my enum Status <OK MORE-INPUT CONTROL>;
my constant @predefined = <Readline Linenoise Fallback>;

PROCESS::<$SCHEDULER>.uncaught_handler =  -> $exception {
    note "Uncaught exception on thread $*THREAD.id():\n"
      ~ $exception.gist.indent(4);
}

# Need to stub first to allow all to see each oher
class REPL { ... }

#- Fallback---------------------------------------------------------------------
role REPL::Fallback {
    has $!OUT-pos;
    has $!ERR-pos;
    has $.history;

    method read($prompt) { prompt $prompt }
    method teardown() { self.save-history }
    method VAL() { $*OUT }
    method OUT() { $!OUT-pos = $*OUT.tell; $*OUT }
    method ERR() { $!ERR-pos = $*ERR.tell; $*ERR }
    method silent() {
        $!OUT-pos == $*OUT.tell && $!ERR-pos == $*ERR.tell
    }
    method history() {
        without $!history {
            if %*ENV<RAKUDO_HIST> -> $history {
                $!history := $history.IO;
            }
            else {
                my $dir   := $*HOME || $*TMPDIR;
                $!history := $dir.add('.raku/rakudo-history');
            }
        }

        unless $!history.e {
            CATCH {
                note "Could not set up history file '$!history':\n  $_.message()";
                .resume;
            }
            $!history.spurt;
        }

        $!history
    }
    method read-history() { }
    method add-history($) { }
    method save-history() { }
}

#- Readline --------------------------------------------------------------------
role REPL::Readline does REPL::Fallback {
    has $!Readline is built;

    method new() {
        with try "use Readline; Readline.new".EVAL {
            self.bless(:Readline($_))
        }
        else {
            Nil
        }
    }

    method read($prompt) {
        $!Readline.readline($prompt)
    }

    method add-history($code --> Nil) {
        $!Readline.add-history($code);
    }

    method read-history() {
        $!Readline.read-history($.history.absolute);
    }

    method save-history() {
        $!Readline.write-history($.history.absolute);
    }
}

#- Linenoise -------------------------------------------------------------------

role REPL::Linenoise does REPL::Fallback {
    has &!linenoise            is built;
    has &!linenoiseHistoryAdd  is built;
    has &!linenoiseHistoryLoad is built;
    has &!linenoiseHistorySave is built;

    method new() {
        with try "use Linenoise; Linenoise.WHO".EVAL -> %WHO {
            self.bless(
              linenoise            => %WHO<&linenoise>,
              linenoiseHistoryAdd  => %WHO<&linenoiseHistoryAdd>,
              linenoiseHistoryLoad => %WHO<&linenoiseHistoryLoad>,
              linenoiseHistorySave => %WHO<&linenoiseHistorySave>,
            );
        }
        else {
            Nil
        }
    }

    method read($prompt) {
        &!linenoise($prompt)
    }

    method add-history($code --> Nil) {
        &!linenoiseHistoryAdd($code);
    }

    method read-history() {
        &!linenoiseHistoryLoad($.history.absolute);
    }

    method save-history() {
        &!linenoiseHistorySave($.history.absolute);
    }
}

#- REPL ------------------------------------------------------------------------
class REPL {

    # The low level compiler to be used
    has Mu   $.compiler      = nqp::getcomp("Raku");

    # When values are shown, use this method on the object
    has Str  $.output-method = %*ENV<RAKU_REPL_OUTPUT_METHOD> // "gist";

    # The values that were recorded in this session, available inside
    # the REPL as $*0, $*1, etc.
    has Mu   @.values;

    # The editor logic being used
    has Mu   $.editor handles <
      add-history ERR OUT read read-history save-history silent teardown VAL
    >;

    # The current NQP context that has all of the definitions that were
    # made in this session
    has Mu   $.context is built(:bind) = nqp::null;

    # Whether it is allowed to have code evalled stretching over
    # multiple lines
    has Bool $.multi-line-ok = !%*ENV<RAKUDO_DISABLE_MULTILINE>;

    # On Windows some things need to be different, this allows an easy check
    has Bool $.is-win  is built(:bind) = $*DISTRO.is-win;

    # Flag whether the extended header should be shown
    has Bool $!header  is built = True;

    # Return state from evaluation
    has Status $.state     is rw = OK;

    # Any exception that should be reported
    has Mu     $.exception is rw is built(False);

    # Number of time control-c was seen
    has int $!ctrl-c;

    method TWEAK() {
        if $*VM.name eq 'moar' {
            signal(SIGINT).tap: {
                if $!ctrl-c++ {
                    self.teardown;
                    exit;
                }
                self.ERR.say: "Pressed CTRL-c, press CTRL-c again to exit";
                print self.interactive_prompt;
            }
        }

        # When running a REPL inside of emacs, the fallback behaviour
        # should be used, as that is provided by emacs itself
        $!editor = REPL::Fallback.new if %*ENV<INSIDE_EMACS>;

        without $!editor {
            for |(REPL::.keys (-) @predefined).keys.sort(*.fc), |@predefined {
                last if $!editor = REPL::{$_}.new;
            }
        }
    }

    method sink() { .repl-loop with self }

    method interactive_prompt() { "[@!values.elems()] > " }

    method repl-loop(:$no-exit) {
        if $!header {
            self.VAL.say: $!compiler.version_string(
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

        # Some initializations
        self.read-history;
        my $last-code = '';

        # Make sure we can reference previous values from within the
        # REPL as $*0, $*1 etc
        my @*_ := @!values;

        REPL: loop {
            # Why doesn't the catch-default in eval catch all?
            CATCH {
                default { say $_; reset }
            }

            # Fetch the code
            my $newcode := self.read($prompt);
            last without $newcode;  # undefined $newcode implies ^D or similar
            last if $no-exit and $newcode eq 'exit';

            $!ctrl-c = 0;
            $code = $code ~ $newcode ~ "\n";
            next if $code ~~ /^ <.ws> $/;  # nothing to work with

            # Evaluate the code
            my $value := self.eval($code, |%_);

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
                self.ERR.say: $!exception.message;
                $!exception = Nil;
            }

            # Print the result if:
            # - there wasn't some other output
            # - the result is an *unhandled* Failure
            elsif self.silent
              or nqp::istype($value,Failure) && not $value.handled {
                my $method := $!output-method;
                CATCH {
                    self.ERR.say: ."$method"();
                    .resume
                }

                self.VAL.say: (nqp::can($value,$method)
                  ?? $value."$method"()
                  !! "(low-level object `$value.^name()`)"
                );

                @!values.push: $value;
            }

            # Add to history if we didn't repeat ourselves
            $code .= trim;
            if $code ne $last-code {
                self.add-history($code);
                $last-code = $code;
            }
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
            temp $*OUT = self.OUT;
            temp $*ERR = self.ERR;
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
        $*MAIN_CTX := nqp::ctxcaller(nqp::ctx());
        $*CTXSAVE  := 0;
    }
}

#- repl ------------------------------------------------------------------------
my sub repl(*%_) is export {
    my $context := nqp::ctxcaller(nqp::ctx);
    REPL.new(:no-exit, :$context :!header, :encoding<utf-8>, |%_)
}

# vim: expandtab shiftwidth=4
