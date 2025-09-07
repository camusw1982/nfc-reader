Create a WebSocket Connection
Call WebSocket library functions (the specific implementation may vary depending on the programming language or library used), passing the request headers and URL to establish a WebSocket connection.

Request :
{
    "Authorization":"Bearer your_api_key", // api key
}

Respond :
{
    "session_id":"xxxx",
    "event":"connected_success"
    "trace_id":"0303a2882bf18235ae7a809ae0f3cca7",
    "base_resp":{
        "status_code":0,
        "status_msg":"success"
    }
}

Send “task_start” event
Sending the task_start event initiates the synthesis task. When the server returns the task_started event, it signifies that the task has successfully begun. Only after receiving this event can you send task_continue or task_finish events to the server.

Request :
{
    "event":"task_start",
    "model":"speech-02-turbo",
    "language_boost":"English",
    "voice_setting":{
        "voice_id":"Wise_Woman",
        "speed":1,
        "vol":1,
        "pitch":0,
        "emotion":"happy"
    },
    "pronunciation_dict":{},
    "audio_setting":{
        "sample_rate":32000,
        "bitrate":128000,
        "format":"mp3",
        "channel":1
    }    
}

Respond :
{
    "session_id":"xxxx",
    "event":"task_started",
    "trace_id":"0303a2882bf18235ae7a809ae0f3cca7",
    "base_resp":{
        "status_code":0,
        "status_msg":"success"
    }
}

Send "task_continue" event
Upon receiving the task_started event from the server, the task is officially initiated. You can then send text to be synthesized via the task_continue event. Multiple task_continue events may be sent sequentially. If no events are transmitted within 120 seconds after the last server response, the WebSocket connection will be automatically terminated.

Request :
{
       "event":"task_continue",
       "text":"Hello, this is the text message for test"
}

Respond :
{
    "data":{
        "audio":"xxx",
    },
    "extra_info":{
        "audio_length":935,
        "audio_sample_rate":32000,
        "audio_size":15597,
        "bitrate":128000,
        "word_count":1,
        "invisible_character_ratio":0,
        "usage_characters":4,
        "audio_format":"mp3",
        "audio_channel":1
    },
    "session_id":"xxxx",
    "event":"task_continued",
    "is_final":false,
    "trace_id":"0303a2882bf18235ae7a809ae0f3cca7",
    "base_resp":{
        "status_code":0,
        "status_msg":"success"
    }
}


Send "task_finish" event
When the task_finish event is sent, the server will wait for all synthesis tasks in the current queue to complete upon receiving this event, then close the WebSocket connection and terminate the task.

Request :
{
    "event":"task_finish"
 }

Reespond :
{
    "session_id":"xxxx",
    "event":"task_finished",
    "trace_id":"0303a2882bf18235ae7a809ae0f3cca7",
    "base_resp":{
        "status_code":0,
        "status_msg":"success"
    }
}

API Call Sample (Websocket)
import asyncio
import websockets
import json
import ssl
from pydub import AudioSegment  # Import audio processing library
from pydub.playback import play
from io import BytesIO

MODULE = "speech-02-hd"
EMOTION = "happy"


async def establish_connection(api_key):
    """Establish WebSocket connection"""
    url = "wss://api.minimax.io/ws/v1/t2a_v2"
    headers = {"Authorization": f"Bearer {api_key}"}

    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE

    try:
        ws = await websockets.connect(url, additional_headers=headers, ssl=ssl_context)
        connected = json.loads(await ws.recv())
        if connected.get("event") == "connected_success":
            print("Connection successful")
            return ws
        return None
    except Exception as e:
        print(f"Connection failed: {e}")
        return None


async def start_task(websocket, text):
    """Send task start request"""
    start_msg = {
        "event": "task_start",
        "model": MODULE,
        "voice_setting": {
            "voice_id": "Wise_Woman",
            "speed": 1,
            "vol": 1,
            "pitch": 0,
            "emotion": EMOTION
        },
        "audio_setting": {
            "sample_rate": 32000,
            "bitrate": 128000,
            "format": "mp3",
            "channel": 1
        }
    }
    await websocket.send(json.dumps(start_msg))
    response = json.loads(await websocket.recv())
    return response.get("event") == "task_started"


async def continue_task(websocket, text):
    """Send continue request and collect audio data"""
    await websocket.send(json.dumps({
        "event": "task_continue",
        "text": text
    }))

    audio_chunks = []
    chunk_counter = 1  # Add chunk counter
    while True:
        response = json.loads(await websocket.recv())
        if "data" in response and "audio" in response["data"]:
            audio = response["data"]["audio"]
            # Print encoding information (first 20 chars + total length)
            print(f"Audio chunk #{chunk_counter}")
            print(f"Encoded length: {len(audio)} bytes")
            print(f"First 20 chars: {audio[:20]}...")
            print("-" * 40)

            audio_chunks.append(audio)
            chunk_counter += 1
        if response.get("is_final"):
            break
    return "".join(audio_chunks)


async def close_connection(websocket):
    """Close connection"""
    if websocket:
        await websocket.send(json.dumps({"event": "task_finish"}))
        await websocket.close()
        print("Connection closed")


async def main():
    API_KEY = "your_api_key_here"
    TEXT = "Hello, this is a text message for test"

    ws = await establish_connection(API_KEY)
    if not ws:
        return

    try:
        if not await start_task(ws, TEXT[:10]):
            print("Failed to start task")
            return

        hex_audio = await continue_task(ws, TEXT)

        # Decode hex audio data
        audio_bytes = bytes.fromhex(hex_audio)

        # Save as MP3 file
        with open("output.mp3", "wb") as f:
            f.write(audio_bytes)
        print("Audio saved as output.mp3")

        # Directly play audio (requires pydub and simpleaudio)
        audio = AudioSegment.from_file(BytesIO(audio_bytes), format="mp3")
        print("Playing audio...")
        play(audio)

    finally:
        await close_connection(ws)


if __name__ == "__main__":
    asyncio.run(main())