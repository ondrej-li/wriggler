# Contributing

`main` is protected: every change lands through a pull request with green CI.

```sh
make generate   # regenerate Wriggler.xcodeproj from project.yml
make test       # build and run the Swift Testing suites
make run        # build, install and launch on a simulator
```

Before opening a pull request:

1. `swift format format --in-place --recursive Sources Tests`
2. `make test`
3. Fill in the pull request template.

Behaviour changes in `Sources/WrigglerCore` should come with tests in
`Tests/WrigglerCoreTests`. Keep rendering (`Sources/Wriggler/Game`) and simulation
(`Sources/WrigglerCore`) separated — the core must not import SpriteKit or UIKit.
