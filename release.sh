#!/bin/sh

export MIX_ENV=prod
export RELEASE_DISTRIBUTION=none

mix compile
npm run deploy --prefix ./assets
mix phx.digest
mix release
