export interface VideoTranscoderPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
