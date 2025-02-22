#- prologue --------------------------------------------------------------------
use nqp;  # hopefully will replace the REPL class in core at some point
use CodeUnit:ver<0.0.3+>:auth<zef:lizmat>;
use Commands:ver<0.0.7+>:auth<zef:lizmat>;
use Edit::Files:ver<0.0.6+>:auth<zef:lizmat>;
use Prompt:ver<0.0.9+>:auth<zef:lizmat>;
use Prompt::Expand:ver<0.0.3+>:auth<zef:lizmat>;
use String::Utils:ver<0.0.32+>:auth<zef:lizmat> <word-at>;

PROCESS::<$SCHEDULER>.uncaught_handler =  -> $exception {
    note "Uncaught exception on thread $*THREAD.id():\n"
      ~ $exception.gist.indent(4);
}

# Context for "=context new"
my $default-context := nqp::ctxcaller(nqp::ctx);
my constant $default-context-name = '(default)';

# Key to exit with
my $exit-letter = $*DISTRO.is-win ?? "^Z" !! "^D";

#- standard completions --------------------------------------------------------

my $uniname-words = try "use uniname-words; &uniname-words".EVAL;
my sub uniname-words(|c) {
    $uniname-words ?? $uniname-words(|c) !! Nil
}

# Set up standard completions
my sub standard-completions($line, $pos is copy = $line.chars) {

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

    # Check for \123, \word completions
    orwith $line.rindex('\\') -> $start is copy {
        without $line.index(' ', $start) {
            if $line.chars > $start {
                my $word   := $line.substr($start + 1).lc;
                my $prefix := $line.substr(0, $start);
                with $word.Int -> $number {
                    ($prefix ~ $number.Str(:superscript),
                     $prefix ~ $number.Str(:subscript))
                }
                orwith $uniname-words && $uniname-words($word) {
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

# Just a visual divider
my multi sub line() {
    say "-" x 70
}
my multi sub line($title) {
    say "-- $title " ~ "-" x 66 - $title.chars;
}

# The active REPL class and Commands object
my $app;
my $commands;
my $helper;

my sub completions($) {
    line expand ":bold:About TAB completions:unbold:";
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

For example, pressing "=", "e", "TAB" will show "=edit".
Pressing TAB again, will show "=exit".  And pressing TAB once
again, will show "=e" again.

If the line does :bold:not:unbold: start with "=", then TAB completions will
attempt to complete to Raku core features.  For instance,
entering "Da", and then pressing TAB repeatedly will cycle
through "Date", "DateTime", "Dateish", all core Raku features.

Finally, some special REPL completions will change the presentation
of the string immediately preceding it.  They are:

\heart - cycle through all unicode codepoints with "heart"
\123  - change integer value to superscript: ¹²³, subscript: ₁₂₃
fOo!   - cycle through FOO, foo, Foo (upper, lower, titlecase)
COMPLETIONS
    line;
}

my sub context-handler($_) {
    my %contexts   := $app.contexts;
    my str $current = $app.context;

    # List the known contexts
    my sub list() {
        for %contexts.keys.sort {
            say ($_ eq $current ?? "* " !! "  ") ~ $_;
        }
    }

    # Need to do something
    if .[1] -> str $action {
        if $action eq 'new' {
            if .[2] -> $new {
                if %contexts{$new} {
                    say "A context named '$new' already exists, did you mean 'switch'?";
                }
                else {
                    $app.set-context($new);
                    say "Created '$new' context and switched to it";
                }
            }
            else {
                say "Must specify a name of a new context";
            }
        }
        elsif $action eq 'switch' {
            if .[2] -> $new {
                if %contexts{$new} {
                    $app.set-context($new);
                    say "Switched to '$new' context";
                }
                else {
                    say "No context '$new' known, these are the known contexts:";
                    list;
                }
            }
            elsif $current eq $default-context-name {
                say "Need to specify the name of the context to switch to";
            }
            else {
                $app.set-context;
                say "Switched back to default context";
            }
        }
        elsif $action eq 'list' {
            list;
        }
        else {
            say "Don't know what to do with '$_'";
        }
    }
    else {
        say "Currently in '$current' context";
    }
}

my sub edit($_) {
    if .[1] // $app.path-of-code -> $file {
        edit-files($file);
    }
    else {
        say "No filename specified, and no default path found";
    }
}

my sub help($_) {
    if .skip.join(" ") -> $deeper {
        $helper.process($deeper)
    }
    else {
        line "Available REPL commands:";
        say $commands.primaries()
          .grep(*.starts-with("=")).join(" ").naive-word-wrapper;
        say "\nMore in-depth help available with '=help <command>'";
    }
}

my sub info($) {
    say "Using the $app.prompt.editor-name() editor.";
}

my sub introduction($) {
    line expand ":bold:Introduction to the Read Evaluate Print Loop:unbold:";
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
This allows you to get to e.g. get to '=help =edit' by entering
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

my sub read($_) {
    if .[1] // $app.path-of-code -> $path {
        $app.path-of-code = $path;
        if $path.IO.slurp -> $code {
            $app.eval($code);
            $app.code = $code;
            say "Executed code found in '$path' ($code.lines.elems() lines)";
        }
        else {
            say "No code found in '$path'";
        }
    }
    else {
        say "Must specify path of to read code from";
    }
}

my sub reset($_) {
    $app.reset;
    say "Status has been reset";
}

my sub stack($) {
    my $bt    := Backtrace.new;
    my @frames = $bt.list;
    if @frames.tail.file.ends-with("bin/repl") {
        say "No stack information inside cold repl";
        return;
    }

    my $this := $bt[1].file;  # skip Backtrace.new itself
    my $index = @frames.first: *.file eq $this, :k, :end;
    without $index {
        say "No sensible stack information found";
        return;
    }

    line "stack";
    .print unless .is-setting || .is-hidden for @frames.skip(++$index);
    put "";

    my $here := $bt[$index];
    my $file := $here.file.subst(/ ' (' <-[)]>+ ')' $$/,'');
    line "file: $file";
    my $current := $here.line;
    my $width   := $current.chars + 1;

    my str @lines = $file eq '-e'
      ?? Rakudo::Internals.PROGRAM.substr(3).lines
      !! ($file.IO.lines // Empty);
    @lines.unshift("");  # make indices 1-based

    for @lines.kv.skip(2) -> $i, $line {
        if $current - 10 < $i < $current + 10 {
            print expand ":bold:" if $i == $current;
            put "$i.fmt("%{$width}d") $line";
            print expand ":unbold:" if $i == $current;
        }
    }
    put "";
}

my sub write($_) {
    if .[1] // $app.path-of-code -> $path {
        $app.path-of-code = $path;
        if $app.code -> @code {
            say (my $result := $path.IO.spurt(@code.join("\n")))
              ?? "Code written to '$path'"
              !! $result;
        }
        else {
            say "No code to save";
        }
    }
    else {
        say "Must specify path of to write code to";
    }
}

#- help support ----------------------------------------------------------------

my constant %help = do {
    my @help =

  completions => q:to/COMPLETIONS/,
Provides information about TAB completions.
COMPLETIONS

  context => q:to/CONTEXT/,
Allows creation of and switching between 2 or more contexts: "new"
creates a new context and switches to it, "switch" switches to an
already existing context, and "list" shows the available contexts.
CONTEXT

  edit => q:to/EDIT/,
Edit the file given, or the last file that was saved with =write.
EDIT

  exit => q:to/EXIT/,
Exit and save any history.
EXIT

  help => q:to/HELP/,
Show available commands if used without additional argument.  If a
command is specified as an additional argument, show any in-depth
information about that command.
HELP

  info => q:to/INFO/,
Show the name of the underlying editor that is being used.  This is
purely informational.  Note that only Linenoise and LineEditor allow
tab-completions.
INFO

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

  read => q:to/READ/,
Read the code from the file with the indicated path and compiles and
executes it.  Remembers the path name so that subsequent =write
commands need not have it specified.
READ

  reset => q:to/RESET/,
Reset the status of the REPL as if it was freshly entered.
RESET

  stack => q:to/STACK/,
Show the caller stack from where the REPL has been called.  Only
makes sense if the REPL is being called from within a program,
rather than from the command line.
STACK

  write => q:to/WRITE/,
Write all lines entered that did *not* produce any output to the
indicated path.  Remembers the path name from =read and =write so
that subsequent =write commands need not have it specified.
WRITE
    ;

    @help.Slip, @help.map({"=$_.key()" => .value}).Slip
}

my sub no-extended($_) {
    say "No extended help available for: $_"
}

my sub moreinfo(Str:D $command, Str:D $text) {
    line "More information about: $command";
    say $text.chomp
}

#- additional completions ------------------------------------------------------

my sub additional-completions($line, $pos) {

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
            elsif $action eq '=context' {
                @targets = <list new switch>;
            }

            @targets.map({ $before ~ $_ ~ $after }).sort(*.fc).List
        }
    }
}

#- REPL ------------------------------------------------------------------------
role REPL:ver<0.0.19>:auth<zef:lizmat> {

    # The codeunit handler (only one for now)
    has Mu  $.codeunit is built(:bind) handles <eval>;
    has str $.context  is built(False) is rw;
    has Mu  %.contexts is built(False);

    # When values are shown, use this method on the object
    has Str $.output-method is rw = %*ENV<RAKU_REPL_OUTPUT_METHOD> // "gist";

    # The values that were recorded in this session, available inside
    # the REPL as $*0, $*1, etc.
    has Mu @.values;

    # The code that caused values to be recorded in this session.
    has str $.path-of-code is rw;
    has str @.code;

    # The prompt logic being used
    has Mu $.prompt handles <
      additional-completions add-history completions editor-name read
      readline load-history save-history supports-completions
    >;

    # Output handles
    has $.out;
    has $.err;
    has $.val;

    # Visible prompt handling
    has Str $.the-prompt = %*ENV<RAKUDO_REPL_PROMPT> // '[:index:] :symbol: ';
    has Str @.symbols;

    # On Windows some things need to be different, this allows an easy check
    has Bool $.is-win is built(:bind) = $*DISTRO.is-win;

    # Flag whether the extended header should be shown
    has Bool $!header is built = True;

    # Number of time control-c was seen
    has int $!ctrl-c;

    method TWEAK(
      Mu :$context = $default-context,
         :$editor,
         :@additional-completions
    ) {
        $!codeunit := CodeUnit.new(:$context, |%_)
          unless nqp::isconcrete( $!codeunit);
        %!contexts{$!context = $default-context-name} := $!codeunit;

        unless $!the-prompt.contains(":symbol:") {
            $!the-prompt ~= $!the-prompt ?? " :symbol: " !! ":symbol: ";
        }

        @!symbols =
          (@!symbols.head // %*ENV<RAKUDO_REPL_SYMBOLS> // ">,*").split(",")
          unless @!symbols > 1;

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

    method reset() {
        @!values   = @!code = ();
        $!codeunit.reset;
    }

    method sink() { .run with self }

    method set-context(
      str $new = $default-context-name
    --> Nil) is implementation-detail {

        if $!context ne $new {

            # save current settings
            %!contexts{$!context} := (
              $!codeunit, @!values, $!path-of-code, @!code
            );

            if %!contexts{$new} -> @info {
                $!codeunit    := @info[0];
                @!values      := @info[1];
                $!path-of-code = @info[2];
                @!code        := @info[3];
            }
            else {
                $!codeunit := CodeUnit.new(:context($default-context));
                @!values   := my Mu @;
                $!path-of-code = "";
                @!code     := my str @;
            }
            $!context = $new;
        }
    }

    method the-prompt() {
        my $state := $!codeunit.state;
        expand($!the-prompt,
          :index(@!values.elems),
          :symbol(@!symbols[$state] // "$state?")
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

    method run() {
        if $!header {
            self.val.say: $!codeunit.compiler-version(:no-unicode($!is-win));
            $!header = False;
        }

        say "To exit type '=quit' or '$exit-letter'. Type '=help' for help.";

        my str $prompt;
        my str $code;
        my sub reset-code(--> Nil) { $code = '' }
        reset-code;

        $app      := self;
        $commands := Commands.new(
          :$!out, :$!err,
          default => {

              # Evaluate the code
              my int $out-tell = $*OUT.tell;
              my int $err-tell = $*ERR.tell;
              my $value := $!codeunit.eval(
                $*INPUT.subst(/ '$*' \d+ /, {
                    '@*_[' ~ $/.substr(2) ~ ']'
                }, :g),
                |%_
              );

              # Handle the special cases
              my $state := $!codeunit.state;
              if $state == MORE-INPUT {
                  next;
              }
              elsif $state == CONTROL {
                  my str $name = $!codeunit.exception.^name.substr(4).lc;
                  say "Control flow command '$name' not allowed in toplevel";
                  $!codeunit.state     = OK;
                  $!codeunit.exception = Nil;
                  reset-code;
                  next;
              }

              # Print an exception if one had occured
              with $!codeunit.exception {
                  note .message.chomp;
                  $!codeunit.exception = Nil;
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

                  # Save code with an additional ";" to mark the end of a
                  # statement if that is needed, to allow the concatenation
                  # later to do the right thing
                  @!code.push: $*INPUT.ends-with(';' | '}')
                    ?? $*INPUT
                    !! "$*INPUT;";
              }
          },
          commands => (
            "=context"   => &context-handler,
            $exit-letter => { last },
            "=exit"      => { last },
            "=quit"      => { last },
            ""           => { next },
            (
              &completions, &edit, &help, &info, &introduction,
              &output, &read, &reset, &stack, &write
            ).map({ "=$_.name()" => $_ }).Slip
          ),
        );

        $helper = $commands.extended-help-from-hash(
          %help, :default(&no-extended), :handler(&moreinfo)
        );

        # Make sure we can reference previous values from within
        # the REPL as $*0, $*1 etc
        my @*_ := @!values;

        loop {
            # Why doesn't the catch-default in eval catch all?
            CATCH {
                default { say $_; reset-code }
            }

            # Set up completions if possible
            self.completions($!codeunit.context-completions)
              if self.supports-completions;

            # Fetch the code
            my $command := $!prompt.readline(self.the-prompt);
            last without $command;

            $!ctrl-c = 0;
            $code    = $code ~ $command ~ "\n";

            $commands.process($code.chomp);
            reset-code;
        }

        self.teardown;
    }
}

#- subroutines -----------------------------------------------------------------

# Debugging aid
my sub repl(*%_) {
    my $context := nqp::ctxcaller(nqp::ctx);
    REPL.new(:$context, :!header, |%_)
}

#- (re-)exporting --------------------------------------------------------------

my sub EXPORT() {
    Map.new(
      "&context"              => &context,
      "&repl"                 => &repl,
      "&uniname-words"        => &uniname-words,
      "&standard-completions" => &standard-completions,
    )
}

# vim: expandtab shiftwidth=4
