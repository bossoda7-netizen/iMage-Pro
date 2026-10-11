# PSD 测试样本

这些文件仅用于兼容测试，不随应用打包。它们由项目自带的标准库脚本生成，不依赖外部 PSD 库。

- `fixture-RAW.psd`、`fixture-RLE.psd`、`fixture-ZIP.psd`、`fixture-ZIP_WITH_PREDICTION.psd`：分别验证 RAW、PackBits RLE、ZIP 和 ZIP 预测压缩，另含中文名称、分组、透明度和通道数据。
- `hidden-layer.psd`：验证单个隐藏图层的显示切换。
- `hidden-groups.psd`：验证隐藏文件夹及其子图层的显示切换。

这些样本只验证本项目支持的 PSD 结构，不代表所有分层工程均可兼容。
