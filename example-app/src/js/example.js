import { VideoTranscoder } from 'capacitor-plugin-video-transcoder';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    VideoTranscoder.echo({ value: inputValue })
}
