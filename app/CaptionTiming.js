function revealOffset(sourceText, displayText, formattedText, words, positionMs) {
  if (typeof sourceText !== "string" || typeof displayText !== "string" ||
      typeof formattedText !== "string" || !Array.isArray(words) || !words.length ||
      typeof positionMs !== "number" || !isFinite(positionMs) || positionMs < 0) return -1
  var previousEnd = 0
  var previousTime = -1
  var end = 0
  for (var i = 0; i < words.length; i++) {
    var word = words[i]
    if (!word || typeof word.startMs !== "number" || !isFinite(word.startMs) ||
        word.startMs < 0 || word.startMs < previousTime ||
        !Number.isInteger(word.endOffset) || word.endOffset <= previousEnd ||
        word.endOffset > sourceText.length) return -1
    previousTime = word.startMs
    previousEnd = word.endOffset
    if (word.startMs <= positionMs) end = word.endOffset
  }
  if (sourceText.slice(previousEnd).trim() !== "") return -1

  // Map template-name substitutions without assuming character counts match.
  var sourceWords = sourceText.match(/\S+/g) || []
  var displayWords = displayText.match(/\S+/g) || []
  if (sourceWords.length !== displayWords.length) return -1
  var sourceTokens = /\S+/g
  var token
  var displayEnd = 0
  var tokenIndex = 0
  var displayTokens = []
  var displayPattern = /\S+/g
  while ((token = displayPattern.exec(displayText)) !== null)
    displayTokens.push({ text: token[0], end: token.index + token[0].length })
  while ((token = sourceTokens.exec(sourceText)) !== null) {
    if (token.index + token[0].length <= end) displayEnd = displayTokens[tokenIndex].end
    else break
    tokenIndex++
  }
  if (displayText.replace(/\s/g, "") !== formattedText.replace(/\s/g, "")) return -1
  var characters = displayText.slice(0, displayEnd).replace(/\s/g, "").length
  if (characters === 0) return 0
  for (var j = 0; j < formattedText.length; j++) {
    if (!/\s/.test(formattedText[j]) && --characters === 0) return j + 1
  }
  return formattedText.length
}

function escapeText(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/\r\n|\r|\n/g, "<br/>")
}

function readingOffset(text, elapsedMs, wordsPerMinute, startOffset) {
  if (typeof elapsedMs !== "number" || !isFinite(elapsedMs) || elapsedMs < 0 ||
      typeof wordsPerMinute !== "number" || !isFinite(wordsPerMinute) || wordsPerMinute <= 0) return -1
  var matches = /\S+/g
  var match
  var ends = []
  while ((match = matches.exec(text)) !== null) ends.push(match.index + match[0].length)
  var alreadyVisible = ends.filter(function(end) { return end <= startOffset }).length
  var count = Math.min(ends.length, alreadyVisible + 1 + Math.floor(elapsedMs * wordsPerMinute / 60000))
  return count > 0 ? ends[count - 1] : text.length
}

function styledText(text, endOffset) {
  if (!Number.isInteger(endOffset) || endOffset < 0 || endOffset >= text.length)
    return escapeText(text)
  return escapeText(text.slice(0, endOffset)) + '<font color="#00000000">' +
    escapeText(text.slice(endOffset)) + "</font>"
}
