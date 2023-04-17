# bdemucs
A bash script that uses demucs to create 4-track multi-tracks or karaoke instrumental versions of your favorite songs and albums

By default, it will work on songs and albums, using the meta data to place the files in a directory tree, and copying the original song metadata to the new file -- with a modification to the filenames and Album titles to denote the alternate version.

## Installation

bdemucs utilizes [demucs](https://github.com/facebookresearch/demucs) and [ffmpeg](https://ffmpeg.org/) to automate the process of creating instrumental/karaoke versions of songs as well as demixed 4-track files including bass.wav, drums.wav, and other.wav (usually guitar).

You must have purchased or ripped audio files from your music collection for it to process, it can not work with streaming services.

The script has been tested with Ubuntu Linux and MacOS Ventura (13.2.1)

### Mac Installation

From a terminal shell

` brew install ffmpeg`

### UNIX Installation

From a terminal shell

`sudo apt update && sudo apt install ffmpeg`

### demucs installation (same for both platforms)

If you just want to use Demucs to separate tracks, you can install it with

`python3 -m pip install -U demucs`

For bleeding edge versions, you can install directly from this repo using

`python3 -m pip install -U git+https://github.com/facebookresearch/demucs#egg=demucs`

## Usage

`./bdemucs.sh -s -o /Users/Me/Instrumentals MySong1.flac`

``` bash
/bdemucs.sh --help

Usage: bdemucs.sh [OPTIONS] INPUT

Options:
  -o, --output-dir DIR         Set the output base directory (default: /Volumes/Media/Instrumentals)
  -s, --save-multitrack        Save multitrack files (default: false)
  -m, --only-multitrack        Only process multitrack files (default: false)
  -a, --append                 String to append to Album title (default: " (Instrumental)")
  -f, --file-append            String to append to file name (default: "_instrumental")
  -d, --debug                  Enable debug mode (default: false)

Input:
  INPUT                        Input files or folders
```


## Todo list

* Add in support for CUDA gpu's. Demucs and the libraries it uses currently don't support the GPU in Silicon Macs, and my Linux machine doesn't have a GPU, so the script is currently hard-coded to use CPUs.
