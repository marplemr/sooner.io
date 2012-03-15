Hook = require('hook.io').Hook
CronJob = require('cron').CronJob
fs = require "fs"

argv = require('optimist')
       .usage("Start a worker process.\nUsage: $0")
       .alias('n', 'name')
       .describe('n', 'name this worker')
       .default('name', 'worker')
       .alias('h', 'host')
       .describe('h', 'host ip address; use own ip if this is to be the main worker process.')
       .default('host', '0.0.0.0')
       .alias('p', 'port')
       .describe('p', 'host port')
       .default('port', 5000)
       .alias('c', 'connect')
       .describe('c', 'connect to a remote host (use this option if not the server)')
       .argv

GLOBAL.hook = hook = new Hook
  name: argv.name

hook.on '**::list-nodes', ->
  hook.emit 'i-am'
    name: hook.name
    host: hook['hook-host']
    port: hook['hook-port']

connDetails =
  'hook-host': argv.host
  'hook-port': argv.port

if argv.connect
  hook.connect connDetails
else
  hook.listen connDetails

# setup db
config = JSON.parse(fs.readFileSync(__dirname + '/config.json'))
mongoose = require 'mongoose'
mongoose.connect "mongodb://#{config.db.host}/#{config.db.name}"
models = require(__dirname + '/app/models')

# setup cron
crons = []
hook.on 'hook::ready', ->
  hook.on '**::reload-workflows', ->
    console.log 'loading workflows into cron...'
    cron.stop() for cron in crons
    models.workflow.find enabled: true, workerName: argv.name, (err, workflows) ->
      if err
        console.log 'error retrieving workflows'
      else
        console.log "workflows: #{JSON.stringify(w.name for w in workflows)}"
        for workflow in workflows
          cron = new CronJob workflow.schedule, ->
            run = workflow.newRun()
            run.save (err, run) ->
              hook.emit 'trigger-job', runId: run._id, name: run.name
          crons.push cron
  hook.on '**::trigger-job', (data) ->
    models.run.findById data.runId, (err, run) ->
      if err or !run
        console.log "Could not find run with id #{data.runId}."
      else
        run.run()
  hook.emit 'reload-workflows'
