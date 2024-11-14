[![Actions Status](https://github.com/lizmat/REPL/actions/workflows/linux.yml/badge.svg)](https://github.com/lizmat/REPL/actions) [![Actions Status](https://github.com/lizmat/REPL/actions/workflows/macos.yml/badge.svg)](https://github.com/lizmat/REPL/actions) [![Actions Status](https://github.com/lizmat/REPL/actions/workflows/windows.yml/badge.svg)](https://github.com/lizmat/REPL/actions)

NAME
====

REPL - a more easily configurable REPL

SYNOPSIS
========

```raku
use REPL;

# Start a repl
repl;
```

DESCRIPTION
===========

The REPL module is a re-imagining of the REPL functionality as offered by Rakudo before the 2024.11 release.

The following goals have been defined so far:

  * Provide an actual REPL class that can be easily configured and provide documentation on how this can be done.

  * Attempt to fix many outstanding bugs about the Rakudo REPL.

  * Provided better documented and better maintainable code that is based on "modern" Raku

  * Once the API for customization is more stable, replace the REPL code in Rakudo with the code in this module.

This is very much a work in progress. Until now, only the `Readline` and `Linenoise` modules are supported. The `Terminal::LineEditor` module will be supported shortly.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/REPL . Comments and Pull Requests are welcome.

If you like this module, or what I'm doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2024 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

