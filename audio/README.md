# Narration files

The validator allows safe relative paths and rejects paths that contain `..`,
so keep audio under the course directory:

```text
courses/
  omarchy-basics.json
  audio/
    open-apps.opus
```

```json
"audio": "audio/open-apps.opus"
```

Opus in an Ogg container is recommended for compact spoken audio. MP3, Ogg,
FLAC, and WAV also work through `mpv`.
