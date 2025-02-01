[![Actions Status](https://github.com/lizmat/REPL/actions/workflows/linux.yml/badge.svg)](https://github.com/lizmat/REPL/actions) [![Actions Status](https://github.com/lizmat/REPL/actions/workflows/macos.yml/badge.svg)](https://github.com/lizmat/REPL/actions) [![Actions Status](https://github.com/lizmat/REPL/actions/workflows/windows.yml/badge.svg)](https://github.com/lizmat/REPL/actions)

NAME
====

REPL - a more easily configurable REPL

SYNOPSIS
========

```raku
use REPL;

# Start a Read, Evaluate, Print Loop
repl;
```

DESCRIPTION
===========

The REPL module is a re-imagining of the REPL (Read, Evaluate, Print Loop) functionality as offered by Rakudo before the 2024.11 release. It provides both a programmable interface, as well as a ready made `"repl"` CLI.

COMMAND LINE INTERFACE
======================

    # Simplest invocation
    $ repl

    # Invocation with some custom settings
    $ repl --editor=Linenoise --output-method=raku --/header

The REPL command-line interface can be invoked with named arguments that have the same name as the named arguments to the `REPL.new` call. They are:

  * --editor - the editor to use (default: Any)

  * --output-method - the output method to be used (default: gist)

  * --header - whether to show the full header (default: yes)

Any other command-line arguments will be ignored.

SUBROUTINES
===========

repl
----

```raku
repl;
```

The `repl` subroutine creates a new `REPL` object for that context and returns that. When called in sink context, it will activate the interactive Read, Evaluate, Print Loop.

```raku
my $repl = do {
    my $a = 42;
    repl
}

# ...

# activate REPL later, allowing access to $a even though that
# variable is no longer in scope
$repl.run;
```

It is also possible to save the `REPL` object at one place in the code, and actually run the REPL at a later time in another scope.

standard-completions
--------------------

The `standard-completions` subroutine provides the standard completion logic if no `:additional-completions` argument has been specified with either `REPL.new` or the `repl` subroutine.

It is provided to allow it to be added with the <:additional-completions> argument, and to allow testing of the standard completion logic.

uniname-words
-------------

The `uniname-words` subroutine provides the same functionality as the `uniname-words` subroutine provided by the [`uniname-words`](https://raku.land/zef:lizmat/uniname-words) distribution **if** that distribution is installed.

Otherwise it will always return `Nil`.

RUNNING A REPL
--------------

The `REPL` role is what usually gets punned into a class.

```raku
my $repl = REPL.new;

$repl.run;
```

Same as above, but with all named arguments spelled out:

```raku
my $repl = REPL.new:
  :editor(Any),    # or "Readline", "LineEditor", "Linenoise"
  :output-method<gist>,  # or "Str", "raku"
  :out = $*OUT,
  :err = $*ERR,
  :val = $*OUT,
  :header,
  :multi-line-ok,
  :the-prompt("[:index:] :symbol: "),
  :symbols(">", "*"),
  :is-win($*DISTRO.is-win),
  :@completions,
  :@additional-completions,
  :compiler<Raku>,
;
```

The `REPL` role embodies the information needed to run a Read, Evaluate, Print Loop. It allows for these named arguments:

### :editor

Optional. String indicating which editor logic to be used.

If the `INSIDE_EMACS` environment variable is set with a true value, then the `Fallback` editor will be used.

If it can be determined from the environment that the process is running inside the "rlwrap" wrapper, then the `Fallback` editor will be used.

If the `RAKUDO_LINE_EDITOR` environment variable is set, then its contents will be assumed as an indication of preference and will first be tried. If that fails, an error message will be shown.

Whatever is then the value, that value will be used to create a [`Prompt`](https://raku.land/zef:lizmat/Prompt) object.

### :output-method

String. The name of the method to be called to display the value of an expression. This defaults to the value of the `RAKU_REPL_OUTPUT_METHOD` environment variable, or to "gist" if that has not been specified.

Used value available with the `.output-method` method.

### :header

Boolean. Indicate whether to show the REPL header upon entry. Defaults to `True`.

Used value available with the `.header` method.

### :out

Optional. The `:out` named argument specifies the value of `$*OUT` whenever a command is executed. If not specified, or specified with an undefined value, will assume the value of `$*OUT` at command execution time.

### :err

Optional. The `:err` named argument specifies the value of `$*ERR` whenever a command is executed. If not specified, or specified with an undefined value, will assume the value of `$*ERR` at command execution time.

### :multi-line-ok

Optional, Boolean. Indicate whether it is ok to interprete multiple lines of input as a single statement to evaluate. Defaults to `True` unless the `RAKUDO_DISABLE_MULTILINE` environment variable has been specified with a true value.

Used value available with the `.multi-line-ok` method.

### the-prompt

Optional. Specifies what will be shown to the user before the user can enter characters. Defaults to what has been specified with the `RAKUDO_REPL_PROMPT` environment variable, or `"[:index:] :symbol: "`.

Supports all of the expansions offered by the [`Prompt::Expand`](https://raku.land/zef:lizmat/Prompt::Expand) distribution.

Note that if there is a prompt (implicitely) specified, the string ":symbol: " will be added if there is no ":symbol:" specified, to make sure the user actually sees a prompting symbol, and to make specifying a user prompt a bit easier.

The expanded prompt is also available with the `.the-prompt` method.

### symbols

Optional. Specifies the symbols that should be used for the `":symbol:"` placeholder in the different REPL states. Defaults to what has been specified as a comma-separated list with the `RAKUDO_REPL_SYMBOLS` environment variable. Defaults to `">", "*"` if that is not specified.

Currently the following states are recognized:

  * 0 - accepting expression to be evaluated

  * 1 - previous expression not complete, accepting continuation

### :is-win

Boolean. Indicate whether certain OS dependent checks should assume Windows semantics. Defaults to `$*DISTRO.is-win`.

Used value available with the `.is-win` method.

### :completions

A `List` of strings to be used tab-completions. If none are specified, then a default Raku set of completions will be used.

Used value available with the `.completions` method.

### :additional-completions

    # completion that uppercases whole line if ended with a !
    sub shout($line, $pos) {
        ($line.chop.uc,) if $pos == $line.chars && $line.ends-with("!")
    }

    my $repl = REPL.new(:additional-completions(&shout));

A `List` of `Callables` to be called to produce tab-completions. If none are specified, the `standard-completions` will be assumed.

Each `Callable` is expected to accept two positional arguments: the line that has been entered so far, and the position of the cursor. It is expected to return a (potentially) empty `List` with the new state of the line (so including everything before and after the completion).

### :prompt

The [`Prompt`](https://raku.land/zef:lizmat/Prompt) object to be used. If specified, overrides anything related to the <C:editor> named argument. If not specified, will use whatever was (implicitely) specified with `:editor`.

### :compiler

String. The HLL compiler to be used. This defaults to "Raku", which is the only compiler supported at this time.

Used value available with the `.compiler` method.

method run
----------

Actually run the REPL.

OTHER METHODS
=============

err
---

The object to be used for error output. Defaults to `$*ERR`.

history
-------

Expected to take no arguments, and return an object that represents the (possibly persistent) history of the REPL's interactive sessions.

By default it will first look for a `RAKUDO_HIST` environment variable and return an `IO::Path` object for that. If that environment variable is not specified, will check the `$*HOME` and `$*TMPDIR` dynamic variables for the existence of a `.raku` subdirectory in that. If found, will return an `IO::Path` for the "rakudo-history" file in that subdirectory and try to create that if it didn't exist yet (and produce an error message if that failed).

out
---

The object to be used for standard output. Defaults to `$*OUT`.

prompt
------

The [`Prompt`](https://raku.land/zef:lizmat/Prompt) object to be used when obtaining input from the user. Also handles the `read`, `readline`, `load-history`, `add-history`, `save-history` and `editor-name` methods.

supports-completions
--------------------

Returns a `Bool` indicating whether the selected editor supports completions.

teardown
--------

Expected to take no arguments. Will be called whenever the user indicates that they want to exit the REPL. Will call the `save-history` method by default.

val
---

The object to be used for outputting values that weren't shown already. Defaults to `$*OUT`.

USER COMMANDS
=============

The following REPL commands are currently supported: if a command is not recognized, then `Raku` code will be assumed and executed if possible. Note that all REPL commands start with "`=`" to prevent confusion with possibly legal Raku code.

editor
------

Shows the name of the editor logic being used. Can be shortened all the way to "=ed".

exit
----

Leaves the REPL. Can be shortened all the way to "=ex".

help
----

Shows a list of available commands. Can be shortened all the way to "=h".

output [method]
---------------

Shows the current output method. If a second argument is specified, it indicates the name of the output method to be used from now on. Typical values are "raku", "Str", "gist". Can be shortened all the way to "=o".

quit
----

Leaves the REPL. Can be shortened all the way to "=q", and is thus the shortest way to leave the REPL with a REPL command.

read [path]
-----------

Read the code from the file with the indicated path and compiles and executes it. Remembers the path name so that subsequent =write commands need not have it specified.

write [path]
------------

Write all lines entered that did **not** produce any output to the indicated path. Remembers the path name from =read and =write so that subsequent =write commands need not have it specified.

TAB COMPLETIONS
===============

If the `supports-completions` method returns `True`, the standard tab-completion logic will provide:

  * all relevant items from the CORE:: namespace

  * any relevant items from the direct context (such as a REPL command)

  * \^123 will tab-complete to ¹²³

  * \_123 will tab-complete to ₁₂₃

  * foo! will tab-complete to FOO, foo, Foo

Additionally, if the [`uniname-words`](https://raku.land/zef:lizmat/uniname-words) module is installed:

  * any unclosed [**\\c[**](https://docs.raku.org/syntax/%5Cc) sequence will tab-complete on the names of Unicode code-points

  * any **\word** will tab-complete to the actual codepoints

ENVIRONMENT VARIABLES
=====================

These environment variables will override default settings.

RAKUDO_REPL_PROMPT
------------------

The prompt shown to the user. May contain escape sequences as supported by the [`Prompt.expand`](https://raku.land/zef:lizmat/Prompt#method-expand) method.

RAKUDO_REPL_SYMBOLS
-------------------

A comma separated list of symbols representing the states of the REPL. Defaults to `>,*>`.

RAKUDO_HIST
-----------

Path where the history file is / should be stored.

RAKU_REPL_OUTPUT_METHOD
-----------------------

The name of the method with which to show results to the user.

RAKUDO_DISABLE_MULTILINE
------------------------

Whether multi-line evaluations should be disabled or not.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/REPL . Comments and Pull Requests are welcome.

If you like this module, or what I'm doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2024, 2025 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

