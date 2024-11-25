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

### :prompt

The [`Prompt`](https://raku.land/zef:lizmat/Prompt) object to be used. If specified, overrides anything related to the <C:editor> named argument. If not specified, will use whatever was (implicitely) specified with `:editor`.

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

Boolean. Indicate whether it is ok to interprete multiple lines of input as a single statement to evaluate. Defaults to `True` unless the `RAKUDO_DISABLE_MULTILINE` environment variable has been specified with a true value.

Used value available with the `.multi-line-ok` method.

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

The following commands are currently supported: if a command is not recognized, then `Raku` code will be assumed and executed if possible.

editor
------

Shows the name of the editor logic being used. Can be shortened all the way to "ed".

exit
----

Leaves the REPL. Can be shortened all the way to "ex".

help
----

Shows a list of available commands. Can be shortened all the way to "h".

quit
----

Leaves the REPL. Can be shortened all the way to "q".

TAB COMPLETIONS
===============

If the `supports-completions` method returns `True`, the standard tab-completion logic will provide:

  * all relevant items from the CORE:: namespace

  * any relevant items from the direct context

  * \^123 will tab-complete to ¹²³

  * \_123 will tab-complete to ₁₂₃

  * foo! will tab-complete to FOO, foo, Foo

Additionally, if the [`uniname-words`](https://raku.land/zef:lizmat/uniname-words) module is installed:

  * any unclosed [**\\c[**](https://docs.raku.org/syntax/%5Cc) sequence will tab-complete on the names of Unicode code-points

  * any **\word** will tab-complete to the actual codepoints

GOALS
=====

The following goals have been defined so far:

  * Adherence to supporting currently by the REPL logic recognized environment variables (done)

  * Provide an actual REPL class that can be easily configured and provide documentation (done)

  * Attempt to fix many outstanding bugs about the Rakudo REPL.

  * Provided better documented and better maintainable code that is based on "modern" Raku (done)

  * Provide a way to support specific commands and their actions so that we don't need any REPL helper modules, but provide an API to provide additional functionality (done)

  * Once the API for customization is more stable, replace the REPL code in Rakudo with the code in this module.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/REPL . Comments and Pull Requests are welcome.

If you like this module, or what I'm doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2024 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

