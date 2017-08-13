require! {
  './joiner': { automation }
  'yargs'
}
say = console.log

argv = yargs
  .usage("Usage: $0 [options]")
  .demandOption("input-dir",  { alias: 'i' describe: 'Input directory with chunked mp4-files' })
  .demandOption("output-dir", { alias: 'o' describe: 'Output directory where joined files are written' })
  .help()
  .argv

input-dir = argv.input-dir
output-dir = argv.output-dir

# Simplify error handeling with this function
bail-if-err = (err, msg) ->
  if err?
    say err
    say msg
    process.exit(255)

# Execute program
(err) <- automation(bail-if-err, input-dir, output-dir)

