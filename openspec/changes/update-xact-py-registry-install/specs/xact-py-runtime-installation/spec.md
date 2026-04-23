## ADDED Requirements
### Requirement: xact-py resolves XAct from Julia registries
`xact-py` SHALL declare the Julia `XAct` dependency using Julia package metadata that resolves the registered package by UUID and version compatibility, not by an embedded local source path.

#### Scenario: Published install resolves registered XAct
- **WHEN** a user installs `xact-py` from PyPI and initializes the runtime
- **THEN** Julia package resolution uses the registered `XAct` package metadata
- **AND** the wheel does not need to include a copy of the Julia package source tree

### Requirement: xact-py runtime does not silently fall back to bundled Julia source
The runtime initialization path SHALL load `XAct` through normal Julia package resolution and MUST raise an actionable import error if `XAct` cannot be loaded.

#### Scenario: Registered package unavailable
- **WHEN** runtime initialization cannot complete `using XAct`
- **THEN** `xact-py` raises an import failure explaining that the Julia `XAct` package could not be loaded
- **AND** the runtime does not activate or include an embedded fallback project

### Requirement: xact-py documents local development against repository sources
The project SHALL document how contributors can use local repository sources during development without depending on a wheel-embedded Julia source bundle.

#### Scenario: Contributor installs editable checkout
- **WHEN** a contributor installs `packages/xact-py` from a local checkout
- **THEN** the documentation explains the additional setup required for `xact-py` to use local Julia sources during development
