#!/bin/sh

export MIX_ENV=prod

mix compile
npm run deploy --prefix ./assets
mix phx.digest
mix release
