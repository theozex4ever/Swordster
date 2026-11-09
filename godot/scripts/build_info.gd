class_name BuildInfo
extends RefCounted
## Identity of this build. The build command overwrites this file in its
## staging copy (never in the working tree), so exported builds show the same
## build ID and source commit that the packaging manifest records.

const BUILD_ID: String = "dev"
const SOURCE_COMMIT: String = "unpackaged"
