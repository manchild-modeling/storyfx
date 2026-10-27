## Installation

Clone the repository:

```bash
git clone https://github.com/manchild-modeling/storyfx.git
cd workspace/storyfx
```

Set up the required Python environments and dependencies using:

```bash
bash setup.sh
```

The setup script installs/configures the environments required by StoryFX, including the dependencies for the main pipeline and external components.

StoryFX additionally requires:

- **Montreal Forced Aligner (MFA)** for transcript–audio alignment
- **Qwen3.8-27B** for SFX composition planning
- **Woosh / Woosh-Flow** for sound-effect generation
- A CUDA-capable GPU for model inference

Pretrained model checkpoints should be downloaded separately and configured in the corresponding pipeline scripts.

## Running

Place the narration audio and transcript under:

```text
data/<excerpt_id>/raw/
```

Run the StoryFX pipeline in the following order:

```text
1. Narrative Temporal Alignment
2. SFX Composition Planning
3. Playback Scheduling
4. SFX Asset Generation
5. SFX Rendering
6. Final Mixing
```

Intermediate outputs are written to `outputs/`, while completed SFX-augmented stories are saved under:

```text
outputs/augmented_stories/
```

Configuration files for prompts and audio-processing presets are located under `configs/`.
