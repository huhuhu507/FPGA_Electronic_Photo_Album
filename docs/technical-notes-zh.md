# 实现说明

## 视频数据路径

电脑先将MP4解码为RGB565帧和48kHz/16位/双声道PCM。每个4×4像素块保存两个RGB565端点及16个2位颜色索引，共8字节；中间两色分别按(2A+B)/3、(A+2B)/3在5/6/5位通道中取整。编码器使用端点主轴和最小二乘迭代，选择误差较小的端点与索引。

SD控制器读取512字节扇区，CRC16校验通过后才将数据交给FAT32加载器。加载器识别BMP、LAV1、LAV2，沿FAT链读取分散簇，将整个素材装入8MiB SDRAM。LAV2在SDRAM中保持压缩；图片和字幕没有经过这种块压缩。

video_reader按下一条显示行提前发起SDRAM读取。压缩图像先确定4行一组的块行，再选择块内子行。bc1_row_decode输出四个像素；写入两次32位行缓存，每个缓存只推导一个物理写端口，避免多端口RAM被展开为大量寄存器。双行缓冲、行标签及坐标流水线保持像素与字幕同步。

## 加载与播放

SD初始化100kHz。数据默认25MHz，SD返回数据在逻辑产生下降沿前采样，给卡片、走线和管脚延迟更多余量；MOSI时序和外部时钟频率保持SPI模式0。每个扇区用CRC16-CCITT（多项式0x1021、初值0）检查；出错可重试，数据时钟依次降至12.5MHz、5MHz，后续读取保留降速结果。三次仍失败报错。读取校验与LAV整包校验都通过后才启播。

motion_player以48kHz PCM采样为时间基准，用samples_per_frame切换源帧，显示帧基地址只在消隐提交；音频从独立异步FIFO输出。视频行优先于音频突发读取。暂停冻结素材时间线；片尾事件跨时钟同步给album_ui，实现视频播完一次后自动下一项。音频真实输出通过HDMI，板载蜂鸣器另用。

顶栏SD显示实际数据时钟档位；LOAD显示上一素材从开始加载到完整装入SDRAM的耗时，0.1秒分辨率。LOAD不包含电脑转码、不代表按键到显示的全部延迟；最后的消隐提交和渐变可能另有少量等待。

## 格式与容量

LAV头512字节，13个小端32位字段：magic、header_bytes、width、height、frames、samples_per_frame、audio_samples、video_words、payload_words、audio_rate、fps、flags、payload_sum32。LAV1 magic=0x3156414C，flags=0/1；LAV2 magic=0x3256414C，flags=2/3，bit0表示原音轨存在，bit1表示压缩。先存全部视频帧，再存交错左右声道PCM；无声音时仍预留等长零PCM，以维持共同时间线。

LAV2宽16..1280、高16..720，宽高均为4的倍数；LAV1宽16..640且偶数、高16..360。帧数1..240，帧率10/12/15/20/24/30，音频48kHz、16位、双声道。LAV2每帧字节数=宽×高/2；每帧对应PCM字节数=48000/帧率×4。最大帧数=min(240, floor(8388608/(视频每帧字节数+PCM每帧字节数)))。每段必须完整装入8MiB，因此时长、分辨率、帧率存在取舍；卡容量大不能增加单段内存容量。

BMP支持24位未压缩BI_RGB，宽16..1280且偶数、高16..720，允许top-down和bottom-up。保留长宽比，显示端可选FIT或FILL；FILL会裁去边缘超出部分。

## 模块分工

hd_clean整合时钟、复位、跨域握手及界面；sd_ctrl提供校验后的扇区；bmp_sdram_loader解释FAT32/BMP/LAV；sdram_ctrl_clean控制板载SDRAM；video_reader负责缩放、裁切和双行缓存；bc1_row_decode解码视频块；motion_player负责帧时间与原声播放；async_audio_fifo跨域传PCM；sdram_read_arbiter协调视频与声音；clip_done_sync同步片尾事件；album_ui处理按键和轮播；signage_osd/font_rom绘制清晰字幕；audio_scope显示音频波形；audio_synth提供静态换片提示；hdmi_tx/tmds_encoder/tmds_serializer形成HDMI信号；number_bcd把数字转换为十进制字符。

解码器采用本项目定义的RGB565精度插值，称为BC1式不透明块编码。它不实现BC1透明模式，不承诺直接接受通用DDS/BC1文件。
