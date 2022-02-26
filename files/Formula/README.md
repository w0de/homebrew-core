### Custom Homebrew Formulae

A brew package is defined by a brew formula. Formulae exist in taps. The default homebrew/core tap includes all default brew packages' formulae.

Ruby formula files may be defined here. Add the define formula's name to `["homebrew-core"]["custom-formulae"]`.

The formula will be added to the node's locally tapped homebrew/cask. The `Homebrew.owner` account, `homebrew_package` resource, can then subsequently install or uninstall the formula's package.

A simple example formula is provided. See Homebrew's docs for a detailed guide to the Formula DSL.
