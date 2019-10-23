    run = require './monitor'
    Config = require 'ccnq4-config'

    module.exports = main = ->
      cfg = await Config()
      run cfg
      true

    if require.main is module
      debug = (require 'tangible') "erratic-reason:server"
      main().catch (error) ->
        debug.dev "Failed to start with error #{error}", error.stack
        process.exit 1
