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

The REPL module is a re-imagining of the REPL (Read, Evaluate, Print Loop) functionality as offered by Rakudo before the 2024.11 release.

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

ROLES
=====

The `REPL` role is what usually gets punned into a class.

The `REPL::Fallback` role provides all of the logic if no specific editor has been found. It also serves as a base role for specific editor roles, such as `REPL::Readline`, `REPL::LineEditor` and `REPL::Linenoise`.

REPL
----

```raku
my $repl = REPL.new;

$repl.run;
```

Same as above, but with all named arguments spelled out:

```raku
my $repl = REPL.new:
  :editor(Any),    # or "Readline", "LineEditor", "Linenoise"
  :output-method<gist>,  # or "Str", "raku"
  :header,
  :multi-line-ok,
  :is-win($*DISTRO.is-win),
  :compiler<Raku>,
;
```

The `REPL` role embodies the information needed to run a Read, Evaluate, Print Loop. It allows for these named arguments:

### :editor

The editor logic to be used. Can be specified as a string, or as an instantiated object that inplements the `REPL::Fallback` role.

If the `INSIDE_EMACS` environment variable is set with a true value, then the `Fallback` editor will **always** be used, regardless of any other settings.

If the `RAKUDO_LINE_EDITOR` environment variable is set, then its contents will be assumed as an indication of preference and will first be tried. If that fails, an error message will be shown.

If the value is not a string, it is expected to be a class that implements to the `REPL::Fallback` interface.

Otherwise defaults to `Any`, which means to search first for unknown roles in the `REPL::` namespace, then to try if there is support installed for [`Readline`](https://raku.land/zef:clarkema/Readline), [`LineEditor`](https://raku.land/zef:japhb/Terminal::LineEditor), or [`Linenoise`](https://raku.land/zef:raku-community-modules/Linenoise).

If that failed, then the `Fallback` editor logic will be used, which may cause a cumbersome user experience, unless the process was wrapped with a call to the [`rlwrap`](https://github.com/hanslub42/rlwrap) readline wrapper.

### :output-method

String. The name of the method to be called to display the value of an expression. This defaults to the value of the `RAKU_REPL_OUTPUT_METHOD` environment variable, or to "gist" if that has not been specified.

Used value available with the `.output-method` method.

### :header

Boolean. Indicate whether to show the REPL header upon entry. Defaults to `True`.

Used value available with the `.header` method.

### :multi-line-ok

Boolean. Indicate whether it is ok to interprete multiple lines of input as a single statement to evaluate. Defaults to `True` unless the `RAKUDO_DISABLE_MULTILINE` environment variable has been specified with a true value.

Used value available with the `.multi-line-ok` method.

### :is-win

Boolean. Indicate whether certain OS dependent checks should assume Windows semantics. Defaults to `$*DISTRO.is-win`.

Used value available with the `.is-win` method.

### :compiler

String. The HLL compiler to be used. This defaults to "Raku", which is the only compiler supported at this time.

Used value available with the `.compiler` method.

### method run

Actually run the REPL.

EDITOR ROLES
============

An editor role must supply the methods as defined by the `REPL::Fallback` role. Its `new` method should either return an instantiated class, or `Nil` if the class could not be instantiated (usually because of lack of installed modules).

The other methods are (in alphabetical order):

add-history
-----------

Expected to take a single string argument to be added to the (possibLy persistent) history of the REPL's interactive sessions. Does not perform any action by default in `REPL::Fallback`.

ERR
---

Expected to take no arguments, and return an object that supports a `.say` method. Will be used instead of the regular `$*ERR` during evalution of the user's input, and to output any error messages during the interacive session. Defaults to `$*ERR` in `REPL::Fallback`.

history
-------

Expected to take no arguments, and return an object that represents the (possibly persistent) history of the REPL's interactive sessions.

By default (by the implementation of the `REPL::Fallback` role will first look for a `RAKUDO_HIST` environment variable and return an `IO::Path` object for that. If that environment variable is not specified, will check the `$*HOME` and `$*TMPDIR` dynamic variables for the existence of a `.raku` subdirectory in that. If found, will return an `IO::Path` for the "rakudo-history" file in that subdirectory and try to create that if it didn't exist yet (and produce an error message if that failed).

load-history
------------

Expected to take no arguments and load any persistent history information, as indicated by its `history` method. Does not perform any action by the default implementation in the `REPL::Fallback` role.

OUT
---

Expected to take no arguments, and return an object that supports a `.say` method. Will be used instead of the regular `$*OUT` during evalution of the user's input. Defaults to `$*OUT` in `REPL::Fallback`.

read
----

Expected to take a string argument with the prompt to be shown, and return the next line of input from the user. Expected to return an undefined value to indicate the user wishes to exit the REPL.

Defaults to showing the prompt and taking a line from `$*IN` in `REPL::Fallback`.

save-history
------------

Expected to take no arguments and save any persistent history information, as indicated by its `history` method. Does not perform any action by the default implementation in the `REPL::Fallback` role.

silent
------

Expected to take no arguments, and return a `Bool` indicating the last evaluation produced any output.

Implemented in the `REPL::Fallback` role as taking the position of the file pointers on `$*OUT` and `$*ERR` (every time the `.OUT` and `.ERR` methods are called) and compare that to their current positions.

If the method returns `True`, then the value `.VAL` method will be used to call the `.say` method on with the value of the last evaluation (converted to string by its `:output-method`.

teardown
--------

Expected to take no arguments. Will be called whenever the user indicates that they want to exit the REPL. Will call the `save-history` method By default in the `REPL::Fallback` implementation.

VAL
---

Expected to take no arguments, and return an object that supports a `.say` method. Will be used instead of the regular `$*OUT` to output the result of an evaluation if that output did not cause any output by itself. Defaults to `$*OUT` in `REPL::Fallback`.

REPL::Fallback
--------------

Apart from the definition of the interface for editors, it provides the default logic for handling the interaction with the user.

REPL::Readline
--------------

The role that implements the user interface using the [`Readline`](https://raku.land/zef:clarkema/Readline) module.

REPL::LineEditor
----------------

The role that implements the user interface using the [`Terminal::LineEditor`](https://raku.land/zef:japhb/Terminal::LineEditor) module.

REPL::Linenoise
---------------

The role that implements the user interface using the [`Linenoise`](https://raku.land/zef:raku-community-modules/Linenoise) module.

GOALS
=====

The following goals have been defined so far:

  * Adherence to supporting currently by the REPL logic recognized environment variables (done)

  * Provide an actual REPL class that can be easily configured and provide documentation (done)

  * Attempt to fix many outstanding bugs about the Rakudo REPL.

  * Provided better documented and better maintainable code that is based on "modern" Raku (done)

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

