# FPGA 智能电子相册

基于安路 EG4S20BG256 / HX4S20C 开发板的本地照片与短视频相册。SD 卡保存素材，FPGA 完成文件解析、SDRAM缓存、视频块解码、比例适配、界面叠加、按键控制和 HDMI 音视频输出。

本仓库为已验收的高清短视频版，源码基线为2026年10月29日，2026年11月2日整理提交。**使用安路 TD 打开根目录 `hd_clean.al`。**

## 已实现功能

- 照片与短视频混合轮播，支持手动切换、自动播放和暂停/继续。
- HDMI 输出1280×720、60Hz；当前短视频素材规格640×480、15帧/秒。
- FIT完整显示、FILL居中裁切铺满，保持近似原比例。
- 独立叠加Logo、运行计时、滚动字幕、素材编号、源尺寸、播放状态和亮度。
- HDMI输出48kHz、16位双声道PCM；波形显示为时域采样窗口。
- SD扇区CRC16校验、失败重试与降速，顶栏显示SD档位和最近加载耗时。
- Flash固化后可断电上电独立播放，无需电脑参与运行。

## 用TD打开和构建

1. 使用安路 TangDynasty TD 4.6.96021，打开 `hd_clean.al`。
2. 顶层模块 `hd_clean`，目标器件 `EG4S20BG256`。工程引用的源码、管脚约束 `hd_clean.adc`、时序约束 `hd_clean.sdc` 均在根目录。
3. 在TD中完成综合、布局布线和时序检查。`build.tcl`给出对应构建步骤。
4. `tools/timing_guard.tcl`检查全部已报告时钟组；通过后才继续生成/下载位流。
5. `bitstream/hd_fixed.bit`是本次已验收位流。下载脚本 `tools/program_jtag.tcl` 和 `tools/program_flash.tcl`分别用于JTAG和SPI Flash，线缆编号需按现场连接核对。

当前最终位流SHA256：

```text
883bdd4bf7db2bb4b7078fbd8028fa827983afe1f1389888a07f93777de7cf11
```

## 素材准备

SD卡使用FAT32，素材放在根目录。扫描前8项有效BMP/LAV文件，顺序由目录扫描决定。BMP要求24位未压缩BI_RGB；宽16～1280且为偶数，高16～720。

手机照片和视频先在电脑上转换。LAV是本项目格式；LAV2使用4×4块、两个RGB565端点和2位索引保存不透明视频，不直接接收MP4、JPEG或通用DDS文件。

```powershell
python -m pip install -r requirements.txt
python tools/prepare_images.py --help
python tools/prepare_motion.py --help
python tools/convert_gui.pyw
```

转换工具可调用PATH上的FFmpeg，或由`imageio-ffmpeg`提供FFmpeg。源代码发布包提供转换脚本和合成测试数据，个人相册素材需自行转换。

视频采用整段预加载，完整载荷不得超过8MiB。640×480、15帧/秒最多50帧，约3.33秒；降低分辨率可增加时长。当前不是边读边播的长视频播放器。

## 按键

| 操作 | 功能 |
|---|---|
| 普通模式短按KEY2 / KEY3 | 下一项 / 上一项 |
| 短按KEY4后松开 | 切换AUTO/HOLD，视频暂停或继续 |
| 同时短按KEY2＋KEY3后松开 | 切换FIT/FILL |
| 长按KEY4约0.8秒 | 进入或退出亮度调节 |
| 亮度模式短按KEY2 / KEY3 | 增加 / 降低媒体亮度，25%～100%共13档 |
| 同时长按KEY2＋KEY3约0.8秒 | 进入或退出彩条网格测试 |

`UPTIME`是上电后的运行时间，不是北京时间；底栏为预置循环字幕。

## 目录

| 路径 | 内容 |
|---|---|
| 根目录`.v`、`.vh` | FPGA逻辑、字模与字符串ROM |
| `hd_clean.al` / `.adc` / `.sdc` | TD工程、管脚与时序约束 |
| `bitstream/` | 当前已验收位流 |
| `tools/` | 图片/视频转换、字模生成、构建检查与下载脚本 |
| `tests/` | RTL测试台、合成磁盘/像素数据、Python工具验证 |
| `reports/` | 最终资源与时序报告 |
| `docs/` | 数据通路、格式、容量和模块说明 |
| `third_party/` | HDMI来源说明与依赖许可 |

## 验证

TD最终资源为LUT 15151/19600、寄存器5219、DSP12、BRAM9K22、PLL2；所报告9个时钟组建立和保持错误均为零，最小裕量为0.172ns / 0.104ns。照片、短视频、自动切换及断电重启已通过板上确认；声音测试于2026年11月1日补充确认通过。

```powershell
python tools/check_build.py
python tests/test_media_tools.py
python tests/test_lav2_tools.py
```

RTL回归脚本使用XSim进行辅助仿真，可把本机Vivado的`bin`目录作为参数传入`tests/run_tests.py`、`tests/run_motion_tests.py`等脚本；FPGA综合、布局布线、时序和下载使用安路TD。所有测试输入均可由`tests/generate_*`脚本生成。

## 第三方来源

HDMI数据包、BCH和TERC4/保护带常量参考`hdl-util/hdmi`，保留其MIT许可证及`third_party/NOTICE.txt`。该部分协议与开源实现不作为本项目原创算法。

更多实现细节见[技术说明](docs/technical-notes-zh.md)。文件完整性可对照根目录`SHA256SUMS.txt`。
