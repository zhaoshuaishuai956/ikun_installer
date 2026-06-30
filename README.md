# 爱坤工具箱 标准化发布流程

## 一、新增插件（三步接入）

### 1. 标记完成
子项目开发完成后，在其目录下创建 `.ready` 空文件：
```
E:\NX二次开发\项目\新插件名\.ready
```

### 2. 配置图标文字
在 `build.ps1` 的 `$subIcon` 映射中添加一行：
```powershell
$subIcon = @{
    ...
    "新插件名" = "图标文字"    # 2个中文字以内, 24x24 BMP 能放下
}
```

### 3. 注册菜单 & 工具栏
编辑 `DeployResources\startup\` 下两个文件（ANSI/GBK 编码）：

**custom.men** — 在 `END_OF_MENU` 前加入：
```
  SEPARATOR

  BUTTON IKUN_XXX
  LABEL 爱坤-功能名称
  BITMAP ikun_新插件名.bmp
  ACTIONS 新插件名.dll
```

**custom.tbr** — 在末尾加入：
```
BUTTON IKUN_XXX
```

> 按钮 ID `IKUN_XXX` 全局唯一，men 和 tbr 中保持一致。

---

## 二、技术约束（插件开发者须知）

### dll 查找 dlx 的规范
**禁止硬编码绝对路径**。dll 必须在运行时通过自身路径找到同目录下的 dlx：
```cpp
// 正确做法 (ejector_layout 入口):
HMODULE hm = NULL;
GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | ...,
                   (LPCSTR)&ufusr, &hm);
if (hm) {
    GetModuleFileNameA(hm, dlxPath, MAX_PATH);
    char* lastSep = strrchr(dlxPath, '\\');
    if (lastSep) *lastSep = '\0';
    strcat_s(dlxPath, MAX_PATH, "\\新插件名.dlx");
}
```

### DLL/DLX 部署
安装器会将 `application\` 下的 dll+dlx 释放到 `D:\Program Files\ikun tools\application\`，两者在同一目录，dll 的同目录查找机制正常工作。

---

## 三、发布操作

```powershell
pwsh -ExecutionPolicy Bypass -File E:\NX二次开发\项目\ikun_installer\build.ps1
```

自动执行 5 步：

| 步骤 | 操作 |
|------|------|
| `[1/5]` | 扫描所有 `.ready` 子项目 → 同步 dll+dlx → 检查/生成 BMP 图标 |
| `[2/5]` | 编译 `ikun_installer.exe`（自包含单文件 win-x64） |
| `[3/5]` | 复制到 `Y:\常用软件\爱坤工具箱\` |
| `[4/5]` | 生成面向用户的 `更新说明.txt` |
| `[5/5]` | 增量备份 `E:\NX二次开发` → `X:\NX二次开发` |

---

## 四、项目结构

```
E:\NX二次开发\项目\
├── ikun_installer\              ← 安装器项目（本文档所在）
│   ├── build.ps1                ← 一键发布脚本
│   ├── ikun_installer.csproj    ← 自包含单文件配置
│   ├── Form1.cs / Program.cs    ← 安装器界面
│   ├── DeployResources\
│   │   ├── startup\             ← 菜单/工具栏/图标
│   │   │   ├── custom.men       ← NX 菜单定义
│   │   │   ├── custom.tbr       ← NX 工具栏定义
│   │   │   └── ikun_*.bmp       ← 各插件按钮图标 (24x24)
│   │   └── application\         ← 插件 dll+dlx (自动同步)
│   └── publish\                 ← 编译产出
├── ejector_layout\              ← 子项目: 顶针快速布局
│   ├── .ready
│   ├── ejector_layout.dll
│   └── ejector_layout.dlx
├── pmi_hole_dim - deepseek\     ← 子项目: PMI孔位标注
│   ├── .ready
│   ├── pmi_hole_dim.dll
│   └── pmi_hole_dim.dlx
└── block_boss_layout\           ← 子项目: 活动块定位凸台
    ├── .ready
    ├── block_boss_layout.dll
    └── block_boss_layout.dlx
```

---

## 五、相关路径

| 路径 | 用途 |
|------|------|
| `E:\NX二次开发\项目\` | 所有子项目根目录 |
| `Y:\1.宛美机械管理资料\1.技术类别\1.常用软件\爱坤工具箱\` | 安装器发布位置 |
| `X:\NX二次开发\` | 全量备份 |
| `D:\Program Files\ikun tools\` | 用户安装目标 |
