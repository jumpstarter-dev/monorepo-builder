# Description

This repository contains a shell script that can be used to join multiple git
repositories into a single monorepo for the jumpstater project.

Those repositories are:

* github.com/jumpstarter-dev/jumpstarter.git -> /python
* github.com/jumpstarter-dev/protocol.git -> /protocol
* github.com/jumpstarter-dev/jumpstarter-controller.git -> /controller
* github.com/jumpstarter-dev/jumpstarter-e2e.git -> /e2e

A top level Makefile is provided and copied to the base of the monorepo.

The monorepo is constructed in ./monorepo using git, and the authorship
and history of the repositories is preserved in the new monorepo.

# Reasoning

This repository is necessary because the jumpstarter project and repos
keep advancing while we work on the monorepo, and we don't want to stop any
development work or make it harder for developers.

It's will be used temporarily, then we can archive this repository as well
as the source repositories, and use the monorepo for development.

