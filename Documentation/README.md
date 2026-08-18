# ScoreMaker API Documentation

For instructions on using the application, see the [ScoreMaker User Manual](USER_MANUAL.md).

The API reference is generated from the autogsdoc comments in `src/*.h`.
From the repository root, run:

```sh
make -f GNUmakefile documentation
```

This requires GNUstep Make and the `autogsdoc` tool supplied by GNUstep Base.
Generated GSdoc and HTML files are written beneath `Documentation/ScoreMaker/`.
They are build artifacts and are not committed.

The generator uses framed navigation. To install the generated reference into
the configured GNUstep documentation hierarchy, run the documentation
makefile's install target directly:

```sh
make -C Documentation -f GNUmakefile install
```
