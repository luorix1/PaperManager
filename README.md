# PaperManager

**PaperManager** is a macOS app for managing academic papers (PDFs) with automatic metadata extraction using either OpenAI's GPT API or a fully local Large Language Model (LLM). The app is designed for privacy, flexibility, and ease of use, supporting both cloud and offline workflows.

---

## Features

- **Import PDFs** and extract metadata (title, authors, publication, year, summary) automatically.
- **Two inference modes:**
  - **GPT API:** Use OpenAI's GPT models (requires your own API key).
  - **Local LLM:** Use a bundled, fully local LLM (Gemma-3-4B-IT-Q4_0) for private, offline extraction.
- **No model downloads at inference time:** Local models are included in the app bundle for instant use.
- **Simple, clean UI** for managing your paper library.
- **Robust JSON extraction:** Handles LLM output with or without markdown formatting.

---

## Getting Started

### 1. **Requirements**

- macOS (Apple Silicon recommended for local LLM)
- Xcode (for building from source)

### 2. **Local LLM Support**

- The app comes with the [Gemma-3-4B-IT-Q4_0](https://huggingface.co/morriszms/gemma-3-4b-it-Q4_0.gguf) model in GGUF format, bundled as a resource.
- No need to download or configure model weights manually.

### 3. **OpenAI GPT API Support**

- Enter your OpenAI API key in the Settings to use GPT-4o for metadata extraction.

---

## Usage

1. **Launch the app.**
2. **Go to Settings** (gear icon or menu):
   - Choose your **Model Source**: `GPT API` or `Local LLM`.
   - If using GPT API, enter your API key.
   - If using Local LLM, Gemma-3-4B-IT-Q4_0 is ready to use (no setup needed).
3. **Import a PDF** using the Import button.
4. The app will extract metadata and add the paper to your library.

---

## How Local LLM Works

- The app uses [LLM.swift](https://github.com/eastriverlee/LLM.swift) to run the Gemma model in GGUF format.
- The model is loaded from the app bundle, not from a user-selected directory.
- The app extracts the JSON object from the LLM output, even if the model returns markdown-formatted code blocks.

---

## Adding More Local Models

- To add more local models, add their `.gguf` files to the `Resources` folder in Xcode and update the code to allow selection.
- Currently, only Gemma-3-4B-IT-Q4_0 is enabled for simplicity and reliability.

---

## Resolving Broken Symlinks for `llama.framework`

To ensure that `llama.framework` is correctly packaged and symlinks are resolved in the `.app` version, you can use the `bundle_llama_framework.sh` script. This script helps fix any broken symlinks that might occur during the packaging process.

### Relevant Files

- `PaperManager/ContentView.swift`
- `bundle_llama_framework.sh`

### Steps to Run the Script

1. **Make the Script Executable:**

   Before running the script, ensure it has executable permissions:

   ```bash
   chmod +x bundle_llama_framework.sh
   ```

2. **Run the Script:**

   Execute the script with the following command, replacing the paths with your specific locations:

   ```bash
   ./bundle_llama_framework.sh \
       ~/Desktop/PaperManager.app \
       ~/Library/Developer/Xcode/DerivedData/PaperManager-*/Build/Products/Debug/llama.framework
   ```

   - The first argument is the path to your packaged `.app` file.
   - The second argument is the path to the `llama.framework` in your build products.

This process is critical for resolving any broken symlinks in the packaged `.app` version for `llama.cpp` (or `llama.framework` as shown in the `.app` contents).

You can visit [LLM.swift on GitHub](https://github.com/eastriverlee/LLM.swift) for the original `llama.framework` files if needed.

---

## Creating a Compressed Version for Release

To create a compressed version of your app for release, you can use the following command:

```bash
7z a -t7z -mx=9 archive.7z $DST
```

- Replace `$DST` with the path to your `.app` file, e.g., `~/PaperManager.app`.
- This command creates a highly compressed `.7z` archive of your app, suitable for distribution.

---

## License

MIT License

---

## Credits

- [LLM.swift](https://github.com/eastriverlee/LLM.swift) for local LLM inference.
- [Gemma-3-4B-IT-Q4_0](https://huggingface.co/morriszms/gemma-3-4b-it-Q4_0.gguf) model.
- OpenAI for GPT API support.

---

**Enjoy managing your papers with privacy and power!**