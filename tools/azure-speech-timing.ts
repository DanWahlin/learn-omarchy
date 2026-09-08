import * as sdk from "microsoft-cognitiveservices-speech-sdk";
import { writeFile } from "node:fs/promises";
import type { WordBoundary } from "./speech-timing.ts";

export function speechWebSocketEndpoint(configuredEndpoint: string): URL {
  const url = new URL(configuredEndpoint);
  if (url.protocol !== "https:" && url.protocol !== "wss:") {
    throw new Error("Azure Speech endpoint must use HTTPS or WSS");
  }
  url.protocol = "wss:";
  url.pathname = url.pathname.replace(/\/+$/, "").replace(/\/cognitiveservices\/v1$/, "") +
    (url.pathname.replace(/\/+$/, "").endsWith("/tts/cognitiveservices/websocket/v1")
      ? "" : "/tts/cognitiveservices/websocket/v1");
  return url;
}

export async function synthesizeWithWordBoundaries(
  text: string, output: string, credentials: { key: string; region?: string; endpoint?: string }, voice: string,
): Promise<WordBoundary[]> {
  const config = credentials.region
    ? sdk.SpeechConfig.fromSubscription(credentials.key, credentials.region)
    : sdk.SpeechConfig.fromEndpoint(speechWebSocketEndpoint(credentials.endpoint!), credentials.key);
  config.speechSynthesisVoiceName = voice;
  config.speechSynthesisOutputFormat = sdk.SpeechSynthesisOutputFormat.Riff24Khz16BitMonoPcm;
  config.setProperty(sdk.PropertyId.SpeechServiceResponse_RequestWordBoundary, "true");
  config.setProperty(sdk.PropertyId.SpeechServiceResponse_RequestPunctuationBoundary, "false");
  config.setProperty(sdk.PropertyId.SpeechServiceResponse_RequestSentenceBoundary, "false");
  const synthesizer = new sdk.SpeechSynthesizer(config, null);
  const boundaries: WordBoundary[] = [];
  synthesizer.wordBoundary = (_, event) => {
    if (event.boundaryType === sdk.SpeechSynthesisBoundaryType.Word) {
      boundaries.push({
        audioOffset: event.audioOffset, textOffset: event.textOffset,
        wordLength: event.wordLength, text: event.text,
      });
    }
  };
  try {
    const result = await new Promise<sdk.SpeechSynthesisResult>((resolve, reject) => {
      synthesizer.speakTextAsync(text, resolve, () => {
        // SDK error details can contain authenticated URLs. Do not log them.
        reject(new Error("Azure Speech SDK synthesis failed (transport or service error)"));
      });
    });
    if (result.reason !== sdk.ResultReason.SynthesizingAudioCompleted) {
      const cancellation = sdk.CancellationDetails.fromResult(result);
      throw new Error(`Azure Speech SDK synthesis failed (reason ${cancellation.reason}, code ${cancellation.ErrorCode})`);
    }
    const bytes = new Uint8Array(result.audioData);
    if (bytes.length < 1000) throw new Error(`Azure Speech SDK returned ${bytes.length} bytes; expected PCM audio`);
    await writeFile(output, bytes);
    return boundaries;
  } finally {
    synthesizer.close();
  }
}
