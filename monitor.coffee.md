    {p_fun} = require 'coffeescript-helpers'

    {debug,heal,foot} = (require 'tangible') 'erratic-reason:monitor'

    request = require 'superagent'
    CouchDB = require 'denormalized-invariants/denormalized'
    uuid = require 'uuid/v4'
    sleep = (timeout) -> new Promise (resolve) -> setTimeout resolve, timeout
    Nimble = require 'nimble-direction'

    set_security = require './set-security'

The couchapp inserted in the user's database, contains the views used by the voicemail application.

    user_app = require 'well-groomed-feast/src/couchapp'

Individual user database changes
--------------------------------

    monitored = (cfg,nimble,doc,data) ->

      {default_voicemail_settings,user_database} = data

### Assign a user-database

If no user-database is specified (but a set of default voicemail settings is present), we create a new database.

* doc.local_number.user_database (string) The name of the user database used to store voicemail messages for that number. Created automatically by the voicemail system, its format is the letter `u` followed by a UUIDv4.
* doc.number_domain.fifos[].user_database (string) The name of the user database used to store voicemail messages for that call group. Created automatically by the voicemail system, its format is the letter `u` followed by a UUIDv4.

      if not user_database?
        unless 'object' is typeof default_voicemail_settings
          debug "Invalid default_voicemail_settings: #{typeof default_voicemail_settings}"
          return
        user_database = "u#{uuid()}"
        data.user_database = user_database
        debug 'Setting user_database', doc
        await nimble.master_push(doc).catch (error) ->
          return if error.status is 409
          debug.dev "monitored: setting user_database: #{error}"

We exit at this point because updating the document will trigger a new `change` event.

        return

### Validate the user-database name

At this point we expect to have a valid user database name.

      if not user_database.match /^u[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
        debug.csr 'Invalid db name', user_database
        return

      target_db_uri = [cfg.userdb_base_uri,user_database].join '/'

### Create the database

Create / access the user database.

      target_db = new CouchDB target_db_uri, true
      debug 'Creating target database', target_db_uri
      await heal target_db.create 1 # single copy
      await target_db.info()

It's OK if the database already exists.

### Build access restrictions

Make sure the users can access it.

      debug 'Setting security', target_db_uri
      await heal 'set_security', set_security target_db

### Limit number of documents revisions

Restrict number of available past revisions

      debug 'Restrict number of available past revisions'

      await request
        .put [target_db_uri,'_revs_limit'].join '/'
        .send '10'
        .catch (error) ->
          debug "Revs limit: #{error}"
          true

### Install the usercode

This is also done in `src/User`, but doing it here ensures the design document is available to outside applications (e.g. a web-based user panel).

      debug 'Insert user application'
      await target_db.merge user_app._id, user_app

### Install the voicemail settings

Create the voicemail settings record.

      VM_ID = 'voicemail_settings'

      vm_settings = await target_db
        .get VM_ID
        .catch -> null

If the voicemail-settings document does not exist, create one based on the default voicemail settings specified.

* doc.local_number.default_voicemail_settings (hash) Object used to initialize the voicemail user database's `voicemail_settings` record. See doc.voicemail_settings for its content.
* doc.number_domain.fifos[].default_voicemail_settings (hash) Object used to initialize the voicemail database's `voicemail_settings` record. See doc.voicemail_settings for its content.
* doc.voicemail_settings._id (string) `voicemail_settings`

      if not vm_settings?
        vm_settings = default_voicemail_settings ? {}
        vm_settings._id = VM_ID

        debug 'Update voicemail settings', vm_settings
        await target_db
          .put vm_settings

### Replicate from another source if requested

      if cfg.replicate_from?
        replication_source = [cfg.replicate_from,user_database].join '/'
        replication_target = if cfg.replicate_to?
            [cfg.replicate_to,user_database].join '/'
          else
            user_database
        await request
          .post [cfg.userdb_base_uri,'_replicate'].join '/'
          .send
            source: replication_source
            target: replication_target

Close.

      target_db = null
      return

Startup
-------

    {invariant} = require 'denormalized-invariants'

    run = (cfg) ->
      if cfg.voicemail?.monitoring is false
        return

      nimble = await Nimble cfg

      debug 'Starting changes listener'
      prov = new CouchDB nimble.provisioning

      invariant 'A configured number should have a voicemail database', prov, (S) ->
        S
        .filter ({type}) -> type is 'number'
        .filter ({default_voicemail_settings,user_database}) ->
          default_voicemail_settings? or user_database?
        .map (doc) ->
          await monitored cfg, nimble, doc, doc

      invariant 'A configured FIFO should have a voicemail database', prov, (S) ->
        S
        .filter ({type}) -> type is 'number_domain'
        .filter ({fifos}) -> fifos?.some (fifo) -> fifo.default_voicemail_settings? or fifo.user_database?
        .map (doc) ->
          return unless doc.fifos?
          for fifo in doc.fifos when fifo.default_voicemail_settings? or fifo.user_database?
            await on_change doc, fifo
          return

      debug 'Ready'
      invariant.start()
      invariant

    module.exports = run
