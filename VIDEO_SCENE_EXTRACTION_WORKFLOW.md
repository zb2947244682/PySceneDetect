# Video Scene Extraction Workflow

This document describes the reusable workflow for batch scene detection and frame extraction on a directory of video files using PySceneDetect.

## Overview

Given a directory containing video files (e.g., `.mp4`), this workflow:

1. Detects scene cuts in each video using `ContentDetector`.
2. Extracts 3 representative frames per scene (start, middle, end).
3. Renames outputs to a standardized format: `{scene_num}_{MMSSFF}_{position}.jpg`.
4. Generates a per-video `index.json` containing scene metadata and per-frame information.

## Environment

- Python >= 3.10
- `scenedetect` installed (this repo, v0.7.1-dev0)
- `opencv-python` (required by scenedetect)
- `ffmpeg` (only needed if splitting video; not required for frame extraction)

## Core Script Template

```python
import os
import json
import glob
import shutil
from pathlib import Path
from scenedetect import open_video, SceneManager, ContentDetector
from scenedetect.output import save_images
from scenedetect.output.image import _generate_timecode_list


def format_mmssff(tc):
    """FrameTimecode -> MMSSFF string.
    Minutes are not zero-padded; seconds and frames are 2-digit.
    Example: 45 min 01 sec 21 frames -> "450121"
    """
    fps = float(tc.frame_rate)
    frame_num = tc.frame_num
    total_seconds = int(frame_num // fps)
    minutes = total_seconds // 60
    seconds = total_seconds % 60
    frames = int(frame_num % fps)
    return f"{minutes}{seconds:02d}{frames:02d}"


def process_video(video_path, output_base_dir, detector_threshold=33.0, num_images=3):
    video_name = Path(video_path).stem
    output_dir = os.path.join(output_base_dir, f"{video_name}_scenes")

    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(output_dir)

    video = open_video(video_path)
    scene_manager = SceneManager()
    scene_manager.add_detector(ContentDetector(threshold=detector_threshold))

    scene_manager.detect_scenes(video=video, show_progress=True)
    scene_list = scene_manager.get_scene_list(start_in_scene=True)
    num_scenes = len(scene_list)

    if num_scenes == 0:
        return 0

    # Extract frames
    video.reset()
    image_filenames = save_images(
        scene_list=scene_list,
        video=video,
        num_images=num_images,
        output_dir=output_dir,
        show_progress=True,
    )

    # Pre-compute exact timecodes for each extracted image
    timecode_list = _generate_timecode_list(scene_list, num_images=num_images, frame_margin=1)

    # Rename and build index
    scenes_data = []
    for i, (start_tc, end_tc) in enumerate(scene_list):
        scene_num = i + 1
        time_str = format_mmssff(start_tc)
        scene_timecodes = timecode_list[i]

        old_images = image_filenames.get(i, [])
        image_details = []
        for j, old_img_rel in enumerate(old_images):
            frame_pos = j + 1  # 1=start, 2=middle, 3=end
            img_tc = scene_timecodes[j]
            old_img_path = os.path.join(output_dir, old_img_rel)
            new_img_name = f"{scene_num}_{time_str}_{frame_pos}.jpg"
            new_img_path = os.path.join(output_dir, new_img_name)
            if os.path.exists(old_img_path):
                os.rename(old_img_path, new_img_path)
                image_details.append({
                    "file": new_img_name,
                    "position": frame_pos,
                    "frame_number": img_tc.frame_num,
                    "timecode": img_tc.get_timecode(),
                    "mmssff": format_mmssff(img_tc),
                })

        scenes_data.append({
            "scene_number": scene_num,
            "start_timecode": start_tc.get_timecode(),
            "end_timecode": end_tc.get_timecode(),
            "start_frame": start_tc.frame_num,
            "end_frame": end_tc.frame_num,
            "duration_frames": end_tc.frame_num - start_tc.frame_num,
            "start_mmssff": time_str,
            "image_files": image_details,
        })

    json_data = {
        "source_video_name": video_name,
        "source_video_path": video_path,
        "resolution": f"{video.frame_size[0]}x{video.frame_size[1]}",
        "frame_rate": str(video.frame_rate),
        "total_scenes": num_scenes,
        "scenes": scenes_data,
    }
    json_path = os.path.join(output_dir, "index.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(json_data, f, ensure_ascii=False, indent=2)

    return num_scenes


def batch_process(input_dir, detector_threshold=33.0):
    video_files = sorted(glob.glob(os.path.join(input_dir, "*.mp4")))
    for idx, video_path in enumerate(video_files, 1):
        print(f"[Progress {idx}/{len(video_files)}] {video_path}")
        process_video(video_path, input_dir, detector_threshold=detector_threshold)
```

## Naming Convention

### Image Files

Format: `{scene_num}_{MMSSFF}_{position}.jpg`

| Component | Meaning | Example |
|-----------|---------|---------|
| `scene_num` | Scene index (1-based) | `1` |
| `MMSSFF` | Minutes (no pad) + Seconds (2-digit) + Frames (2-digit) | `450121` = 45m 01s 21f |
| `position` | Frame position within scene: `1`=start, `2`=middle, `3`=end | `2` |

Example: `1_450121_2.jpg` = Scene 1, starts at 45:01:21, middle frame.

### Output Directory

Each video gets a folder named `{video_name}_scenes/` containing:
- All extracted images
- `index.json` (scene metadata)

## JSON Index Format

```json
{
  "source_video_name": "E01 林黛玉别父进京都",
  "source_video_path": "D:/.../E01 林黛玉别父进京都.mp4",
  "resolution": "720x576",
  "frame_rate": "25",
  "total_scenes": 305,
  "scenes": [
    {
      "scene_number": 1,
      "start_timecode": "00:00:00.000",
      "end_timecode": "00:00:08.840",
      "start_frame": 0,
      "end_frame": 221,
      "duration_frames": 221,
      "start_mmssff": "00000",
      "image_files": [
        {
          "file": "1_00000_1.jpg",
          "position": 1,
          "frame_number": 1,
          "timecode": "00:00:00.040",
          "mmssff": "00001"
        },
        {
          "file": "1_00000_2.jpg",
          "position": 2,
          "frame_number": 111,
          "timecode": "00:00:04.440",
          "mmssff": "00004"
        },
        {
          "file": "1_00000_3.jpg",
          "position": 3,
          "frame_number": 220,
          "timecode": "00:00:08.800",
          "mmssff": "00008"
        }
      ]
    }
  ]
}
```

## Tunable Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `detector_threshold` | `33.0` | `ContentDetector` threshold. Higher = fewer scenes. Default `27.0` is too sensitive for most content; `33.0` yields ~300-310 scenes per 45-min episode. |
| `num_images` | `3` | Frames extracted per scene. Positions map to: `1`=start, `2`=middle, `3`=end. |
| `frame_margin` | `1` | Margin (in frames) from scene boundaries when picking start/end frames. Passed to `_generate_timecode_list`. |

### Threshold Calibration

If the target scene count is known (e.g., ~307 scenes), test a few thresholds on one representative video before batch processing:

```python
for threshold in [30.0, 32.0, 33.0, 34.0, 35.0]:
    video = open_video(video_path)
    sm = SceneManager()
    sm.add_detector(ContentDetector(threshold=threshold))
    sm.detect_scenes(video=video, show_progress=False)
    print(f"threshold={threshold}: {len(sm.get_scene_list(start_in_scene=True))} scenes")
```

## Optional: Video Splitting

If split MP4s are also required, use `split_video_ffmpeg` after detection:

```python
from scenedetect.output import split_video_ffmpeg

# Fast copy-mode (no re-encode) — may have slight keyframe drift
FFMPEG_ARGS_FAST = "-map 0:v:0 -map 0:a? -map 0:s? -c:v copy -c:a copy"

split_video_ffmpeg(
    input_video_path=video_path,
    scene_list=scene_list,
    output_dir=output_dir,
    output_file_template="$VIDEO_NAME-Scene-$SCENE_NUMBER.mp4",
    arg_override=FFMPEG_ARGS_FAST,
    show_progress=True,
)
```

For frame-accurate cuts, omit `arg_override` to use the default re-encode settings (much slower).

## Notes

- `save_images` returns a dict with **0-based** scene indices as keys.
- `_generate_timecode_list` is an internal API; import from `scenedetect.output.image`.
- The `mmssff` format intentionally does **not** zero-pad minutes so the string length varies for sub-10-minute scenes (`50101` = 5m 01s 01f).
