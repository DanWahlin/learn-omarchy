# Narration files

The validator allows safe relative paths and rejects paths that contain `..`,
so keep audio under the course directory:

```text
courses/
  omarchy-basics.json
  audio/
    hexon/open-apps.opus
    owl/open-apps.opus
```

```json
"audio": "audio/open-apps.opus"
```

The course names the file without a coach; the app inserts the selected
coach's id as a directory, since each coach records its own narration.

Opus in an Ogg container is recommended for compact spoken audio. MP3, Ogg,
FLAC, and WAV also work through `mpv`.
