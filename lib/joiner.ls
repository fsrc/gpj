# DEPENDENCIES
require! {
  fs : { readdir, write-file }
  'prelude-ls' : { fold, sort, filter, map, flatten }
  'child_process' : { exec, spawn }
  'async-ls' : { callbacks }
  'process': { stdout }
  'moment'
}
{ serial-map } = callbacks

# ALIASES
######################################
out = (output-string) -> stdout.write(output-string)
say = console.log
######################################
# ALIASES

# CONSTANTS
######################################
input-directory  = "/mnt/enduro/org"
output-directory = "/mnt/enduro/stitched"
######################################
# CONSTANTS

# REGEXES
######################################
regex-root-file    = /^GOPR(\d{4})\.MP4/
regex-sub-file     = /^GP\d\d(\d{4})\.MP4/
regex-created-date = /creation_time\s+:\s(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)/
######################################
# REGEXES

# CLI COMMANDS
######################################
# cli-info-mp4-file       = "MP4Box -info"
cli-info-mp4-file       = (file) -> "ffmpeg -i #{file}"
cli-concat-mp4-files    = (list-file, output-file) -->
  cmd: "ffmpeg"
  args:['-y', '-f', 'concat', '-safe 0', "-i #{list-file}", "-c copy", "#{output-file}"]
######################################
# CLI COMMANDS

# DYNAMIC FILE NAMES
######################################
file-for-sequence = (path, ext, sequence) -> "#{path}/#{sequence.name}.#{ext}"
######################################
# DYNAMIC FILE NAMES

# FILTERS
######################################
export only-root-files = filter (item) -> regex-root-file.test(item)
export only-sub-files  = filter (item) -> regex-sub-file.test(item)
export only-actual-sequences = filter (item) -> item.length > 1
only-sub-files-to-sequence = (sequence-id) -> filter (item) ->
  regex-sub-file.exec(item).1 == sequence-id
######################################
# FILTERS

# DECORATIONS
######################################
# root file with sequence
export decorate-root-file-with-sequence = (sub-files, item) -->
  sequence-sub-files =
    only-sub-files-to-sequence(
      regex-root-file.exec(item).1)( # sequence-id
      sub-files)
  flatten([item, sequence-sub-files])

# filename with mp4 date
decorate-filename-with-mp4-date = (path, file-name, callback) -->
  out file-name + "\t"
  (err, stdout, stderr) <- exec(cli-info-mp4-file(file-name), { cwd: path })
  match-str = regex-created-date.exec(stderr)
  if match-str == null
    say(stderr)
    callback(stderr)
  else
    say(match-str.1)
    callback(null, {file: file-name, date: Date.parse(match-str.1) })

# create a valid name for the sequence
export decorate-sequences-with-name = fold((acc, sequence) ->
  date-str = moment(sequence.0.date).format('YYYY-MM-DD')
  if not acc[date-str]?
    acc[date-str] = 1
  else
    acc[date-str] += 1
  sequence.name = "#{date-str}##{acc[date-str]}"
  acc
)({})

# sequence with mp4 dates
export decorate-sequences-with-mp4-dates = (path) ->
  decorate-sequences-with-mp4-dates-path = decorate-filename-with-mp4-date(path)
  serial-map (file-names, callback) ->
    serial-map(decorate-sequences-with-mp4-dates-path, file-names, callback)

######################################
# DECORATIONS


# Create a ffmpeg list file for concatination
######################################
export write-demuxer-file = (path, sequence, callback) -->
  output-file  = file-for-sequence(path, \txt, sequence)
  demuxer-line = (sequence-track) -> "file '#{path}/#{sequence-track.file}' # #{sequence-track.date}"
  demuxer-lines = map(demuxer-line, sequence).join(\\n)

  (err) <- write-file(output-file, demuxer-lines, enc:\utf8)
  callback(err)
######################################
# Create a ffmpeg list file for concatination

# EXEC CLI - concatinate mp4 files with ffmpeg
######################################
export concat-mp4-files = (input-directory, output-directory, sequence, callback) -->

  list-file   = file-for-sequence(input-directory, \txt, sequence)
  output-file = file-for-sequence(output-directory, \mp4, sequence)

  { cmd, args } = cli-concat-mp4-files(list-file, output-file)

  concat-process = spawn(cmd, args, {shell:true, input-directory})

  concat-process.stderr.on(\data, (output) -> out(output))
  concat-process.stdout.on(\data, (output) -> out(output))
  concat-process.stdout.on(\end, -> callback(null, 'done'))

######################################
# EXEC CLI - concatinate mp4 files with ffmpeg


# MAIN
######################################
export automation = (bail-if-err, input-directory, output-directory, callback) ->
  # Read all mp4 files available in input-directory
  (err, files) <- readdir(input-directory)
  bail-if-err(err, "Could not read input directory")

  root-files       = only-root-files(files)
  sub-files        = only-sub-files(files) |> sort
  sequences        = root-files |> map(decorate-root-file-with-sequence(sub-files))
  actual-sequences = only-actual-sequences(sequences)

  # Read date and time from mp4 files and decorate sequence with info
  (err, decorated-sequences) <- decorate-sequences-with-mp4-dates(input-directory)(actual-sequences)
  bail-if-err(err, "Could not extract timestamp from mp4 files")

  decorate-sequences-with-name(decorated-sequences)

  # Join the sequences into files and name them acording to date
  (err) <- serial-map(write-demuxer-file(input-directory), decorated-sequences)
  bail-if-err(err, "Could not write demuxer file")

  (err) <- serial-map(concat-mp4-files(input-directory, output-directory), decorated-sequences)
  bail-if-err(err, "Could not write output mp4 file")

  callback!
######################################

