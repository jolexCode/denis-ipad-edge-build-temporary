# Denis iPad Edge — temporary build source

This repository contains only the native iPadOS client and its reproducible
Xcode 26 build workflow. It intentionally excludes the Denis server runtime,
Persona, Agency, infrastructure configuration, credentials, signing material,
receipts, memory, and private network addresses.

The application is an edge capability host. Server-defined requests can use
its stable Apple-framework connectors without rebuilding the IPA. All model
outputs remain candidate-only and require admission by Denis Persona.
