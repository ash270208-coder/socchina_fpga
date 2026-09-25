data/ 目录说明（把资料按下面规则放进来即可）

【images/】——训练图片放这里（支持 .jpg .jpeg .png .bmp）
  - 有人脸的图：同时在 boxes.csv 里标注
  - 没人脸的背景图（负样本）：直接放进来就行，不用标注（step1 自动当负样本）
  - 建议：正常脸 100~200 张；涂颜料脸 50~100 张（核心需求！）；负样本 50~100 张

【test/】——测试图放这里（不参与训练）
  - step4_golden_forward 会自动取这里的第一张图做定点前向验证；
  - 若在 matlab/cnn_detector/ 根目录放 test.jpg，则优先用 test.jpg

【boxes.csv】——标注文件
  - 每行：文件名,x,y,w,h（左上角坐标，像素）
  - 一张图多个框就写多行；第一行表头保留即可（脚本自动跳过）
  - 示例：
      img001.jpg,120,80,60,70
      img001.jpg,300,200,80,95
      img002.jpg,150,90,55,62
  - 文件名只写 basename（如 img001.jpg），不要带路径

【标框工具】——不用手算坐标，两种方式：
  1) 半自动（推荐）：跑 step1b_autolabel —— 内置人脸检测器自动标框写 boxes.csv；
     涂颜料的脸会漏检，脚本末尾会列出漏检名单，只对它们用 imageLabeler 手动补框；
  2) 全手动：MATLAB 命令行输入 imageLabeler → 打开图片目录 → 鼠标画矩形框
     （坐标由软件自动记录，不用自己看）→ Export Labels 导出；
     导出格式不匹配没关系，贴给 AI 转成 boxes.csv

【WIDER FACE（可选，用于多样性）】
  - 下载 wider_face_train_bbx_gt.txt + WIDER_train/images，把路径填进 step1_prepare_data；
  - 选图不用手动挑：parse_widerface.m 自动过滤（脸太小/太大、严重模糊、夸张姿态、重度遮挡）；
  - 推荐最终用 mode='AB'：WIDER 提供多样性，自拍提供彩绘脸/负样本/演示环境域匹配

【跑法】
  - step1b_autolabel      → （可选）半自动标框，生成 boxes.csv
  - step1_prepare_data   → 生成 training_data.mat（脚本里 mode：'A' 自采 / 'B' WIDER / 'AB' 混合）
  - step2_train_detector → 训练（生成 detector_trained.mat）
  - step3_quantize_export→ 量化导出 .mem（生成 out/ 目录）
  - step4_golden_forward → 定点金标准对比
