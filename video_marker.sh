#!/bin/bash

# 使用说明
usage() {
    echo "Usage: $0 <input_video> <watermark_text> <output_directory>"
    echo "input_video: The path to the input video file."
    echo "watermark_text: The text content of the watermark."
    echo "output_directory: The directory where the output video will be saved."
    exit 1
}

# 检查参数个数
if [ "$#" -ne 3 ]; then
    usage
fi

# 检查ffmpeg和ffprobe是否已安装
if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null
then
    echo "ffmpeg or ffprobe could not be found, please install them first."
    exit 1
fi

# 检查marker.py脚本是否存在
if [ ! -f "marker.py" ]; then
    echo "marker.py does not exist in the current directory."
    exit 1
fi

# 设置变量
INPUT_VIDEO=$1
WATERMARK_TEXT=$2
OUTPUT_DIR=$3
FILENAME=$(basename -- "$INPUT_VIDEO")
OUTPUT_VIDEO="$OUTPUT_DIR/${FILENAME%.*}_watermarked.mp4"

# 创建文件夹
TMP_DIR="./tmp"
FRAME_DIR="$TMP_DIR/frames"
WATERMARKED_FRAMES_DIR="$TMP_DIR/watermarked_frames"
mkdir -p $FRAME_DIR
mkdir -p $WATERMARKED_FRAMES_DIR
mkdir -p $OUTPUT_DIR

# 获取视频的帧率
FRAME_RATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO" | bc)

# 如果无法获取帧率，则使用默认值24
if [ -z "$FRAME_RATE" ]; then
    FRAME_RATE=24
fi

# 获取视频的总帧数，并去除数字中的逗号
TOTAL_FRAMES=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")

# 计算输出文件名的格式
DIGITS=${#TOTAL_FRAMES}

# 获取输入视频的比特率
BIT_RATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")

# 检查获取到的比特率是否为数字
if ! [[ $BIT_RATE =~ ^[0-9]+$ ]]; then
    BIT_RATE=""
else
    BIT_RATE="-b:v $BIT_RATE"
fi

echo "==============================="
echo "FRAME_RATE: $FRAME_RATE"
echo "TOTAL_FRAMES: $TOTAL_FRAMES"
echo "DIGITS: $DIGITS"
echo "BIT_RATE: $BIT_RATE"
echo "==============================="

# 解帧为png图片，不再指定帧率，以保留原始帧率
echo "extracting frames..."
ffmpeg -hide_banner -v error -i "$INPUT_VIDEO" "$FRAME_DIR/frame_%0${DIGITS}d.png"

# 使用marker.py给整个目录的图片添加水印
python marker.py -f "$FRAME_DIR" -m "$WATERMARK_TEXT" -o "$WATERMARKED_FRAMES_DIR"

# 把水印图片重新编码为输出视频，保持原始帧率，并复制音频流
echo "encoding frames to video..."
ffmpeg -hide_banner -v error -framerate $FRAME_RATE -i "$WATERMARKED_FRAMES_DIR/frame_%0${DIGITS}d.png" -i "$INPUT_VIDEO" -c:v libx264 -preset veryslow $BIT_RATE -pix_fmt yuv420p -c:a copy -map 0:v:0 -map 1:a:0 "$OUTPUT_VIDEO"

RET=$?

# 清理临时文件夹（可选）
# rm -rf $FRAME_DIR
# rm -rf $WATERMARKED_FRAMES_DIR
echo "removing tmp files..."
rm -rf $TMP_DIR

if [ $RET -ne 0 ];then
    echo "some error occured!"
    exit $RET
fi
echo "Watermarked video has been created: $OUTPUT_VIDEO"