/* ============================================================
 *  {{NAME}}.cpp  -  NX 二次开发 Block Styler 对话框示范 (NX 1847)
 *  由 nx-blockstyler-dev skill 生成的模板。
 *
 *  演示控件: 标签 / 字符串 / 枚举 / 表达式x2 / 整数 / 开关 / 按钮
 *  演示读值: GetString / GetEnum / Expression->Value() / GetInteger / GetLogical
 *  演示建模: UF_MODL_create_block1 / _cyl1 / _sphere1 (WcsGuard 保护)
 *
 *  入口: ufusr (NX -> Ctrl+U -> 选择本 dll)
 *  dlx 路径: 运行时自动取"与 dll 同目录、同名的 .dlx"，
 *            改工程名/移动目录都无需改代码（坑账§7）。
 * ============================================================ */
#include <windows.h>
#undef CreateDialog   /* windows.h 的宏会毁掉 UI::CreateDialog (坑账§3) */
#undef max
#undef min

#include <uf.h>
#include <uf_modl.h>
#include <uf_csys.h>
#include "nx_demo.hpp"
#include "ikun_update_check.hpp"
#include <string>
#include <sstream>
#include <vector>
#include <cstdio>

using namespace NXOpen;
using namespace NXOpen::BlockStyler;

NXOpen::Session *NxDemo::theSession = NULL;
NXOpen::UI      *NxDemo::theUI      = NULL;

enum SolidType { TYPE_BLOCK = 0, TYPE_CYLINDER = 1, TYPE_SPHERE = 2 };

/* 尺寸上限(mm)：防止超大输入把 sprintf 缓冲区撑爆 / 生成病态几何 */
static const double kMaxDim = 100000.0;

/* -------- WcsGuard: UF_MODL_* 图元按当前 WCS 定位, 不是绝对系。
 * 操作期间临时把 WCS 设为绝对系, 离开(含异常)自动还原 (坑账§4★)。 */
struct WcsGuard {
    tag_t saved; bool ok;
    WcsGuard(): saved(NULL_TAG), ok(false) {
        if (UF_CSYS_ask_wcs(&saved) != 0) return;
        double m[9] = {1,0,0, 0,1,0, 0,0,1}, o[3] = {0,0,0}; tag_t mt = 0, cs = 0;
        if (UF_CSYS_create_matrix(m, &mt) == 0 && UF_CSYS_create_temp_csys(o, mt, &cs) == 0
            && UF_CSYS_set_wcs(cs) == 0) ok = true;
    }
    ~WcsGuard() { if (ok && saved != NULL_TAG) UF_CSYS_set_wcs(saved); }
};

/* -------- PlGuard: PropertyList 用完必须 delete, 含异常路径 (坑账§2) */
struct PlGuard {
    PropertyList* p;
    ~PlGuard() { delete p; }
};

/* -------- 取"与本 dll 同目录、同名"的 dlx 绝对路径 (坑账§7) */
static std::string dlxPathBesideDll()
{
    HMODULE h = NULL;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                       GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCSTR)&dlxPathBesideDll, &h);
    char p[MAX_PATH] = {0};
    GetModuleFileNameA(h, p, MAX_PATH);
    std::string s(p);
    size_t dot = s.find_last_of('.');
    if (dot != std::string::npos) s.resize(dot);
    return s + ".dlx";
}

/* -------- 构造 / 析构 -------- */
NxDemo::NxDemo(const char* dlxPath)
{
    theSession = Session::GetSession();
    theUI      = UI::GetUI();
    theDlxFileName = dlxPath;

    theDialog = theUI->CreateDialog(theDlxFileName.c_str());
    theDialog->AddInitializeHandler(make_callback(this, &NxDemo::init_cb));
    theDialog->AddApplyHandler     (make_callback(this, &NxDemo::apply_cb));
    theDialog->AddOkHandler        (make_callback(this, &NxDemo::ok_cb));
    theDialog->AddCancelHandler    (make_callback(this, &NxDemo::cancel_cb));
    theDialog->AddUpdateHandler    (make_callback(this, &NxDemo::update_cb));
}

NxDemo::~NxDemo() { if (theDialog) { delete theDialog; theDialog = NULL; } }
void NxDemo::Show() { theDialog->Show(); }

/* -------- init_cb: 绑定控件指针 (NX1847 中返回 void) --------
 * 关键1: TopBlock() 返回 CompositeBlock*, FindBlock 是它的成员。
 * 关键2: 枚举下拉项 dlx 里写的 <Items> 在 NX1847 常不填充(中文必空),
 *        必须在这里运行时 SetEnumMembers(UTF8) (坑账§1)。          */
void NxDemo::init_cb()
{
    CompositeBlock* top = theDialog->TopBlock();
    group_main  = dynamic_cast<Group*>       (top->FindBlock("group_main"));
    lbl_info    = dynamic_cast<Label*>       (top->FindBlock("LBL_INFO"));
    str_name    = dynamic_cast<StringBlock*> (top->FindBlock("STR_NAME"));
    enum_type   = dynamic_cast<Enumeration*> (top->FindBlock("ENUM_TYPE"));
    expr_a      = dynamic_cast<ExpressionBlock*>(top->FindBlock("DBL_A"));
    expr_b      = dynamic_cast<ExpressionBlock*>(top->FindBlock("DBL_B"));
    int_count   = dynamic_cast<IntegerBlock*>(top->FindBlock("INT_COUNT"));
    tgl_notify  = dynamic_cast<Toggle*>      (top->FindBlock("TGL_HL"));
    btn_preview = dynamic_cast<Button*>      (top->FindBlock("BTN_PREVIEW"));

    if (enum_type) {
        std::vector<NXString> items;
        items.push_back(NXString("长方体", NXString::UTF8));
        items.push_back(NXString("圆柱体", NXString::UTF8));
        items.push_back(NXString("球体",   NXString::UTF8));
        enum_type->SetEnumMembers(items);
    }
}

/* -------- 统一读取各控件值 --------
 * getter 必须与控件类型匹配, 否则抛 "属性类型不正确":
 *   String->GetString  Integer->GetInteger
 *   Enumeration->GetEnum(!!)  Toggle->GetLogical
 * 数值输入用 ExpressionBlock(支持表达式/单位), 读值 b->Value(),
 * 不走 PropertyList (坑账§2"数值输入一律用表达式块")。            */
void NxDemo::readValues(std::string& name, int& type,
                        double& a, double& b, int& count, bool& notify)
{
    name = "Demo"; type = 0; a = 100.0; b = 60.0; count = 1; notify = true;

    if (str_name)  { PlGuard g{ str_name->GetProperties() };  name  = g.p->GetString("Value").GetText(); }
    if (enum_type) { PlGuard g{ enum_type->GetProperties() }; type  = g.p->GetEnum("Value"); }   // 枚举用 GetEnum
    if (expr_a)    a = expr_a->Value();   // 表达式块直接 Value(), 不走 PropertyList (坑账§2)
    if (expr_b)    b = expr_b->Value();
    if (int_count) { PlGuard g{ int_count->GetProperties() }; count = g.p->GetInteger("Value"); }
    if (tgl_notify){ PlGuard g{ tgl_notify->GetProperties() };notify= g.p->GetLogical("Value"); }
}

/* -------- [显示参数] 按钮: 弹出当前参数 -------- */
void NxDemo::showParams()
{
    std::string name; int type, count; double a, b; bool notify;
    readValues(name, type, a, b, count, notify);
    const char* tn[3] = { "长方体", "圆柱体", "球体" };
    std::ostringstream os;
    os << "当前参数:\n"
       << "  模型名称 : " << name << "\n"
       << "  图元类型 : " << ((type>=0&&type<=2)?tn[type]:"未知") << "\n"
       << "  尺寸 A   : " << a << " mm\n"
       << "  尺寸 B   : " << b << " mm\n"
       << "  阵列数量 : " << count << "\n"
       << "  完成提示 : " << (notify?"开":"关");
    theUI->NXMessageBox()->Show("参数预览", NXMessageBox::DialogTypeInformation, os.str().c_str());
}

/* -------- 按参数创建实体, 支持沿 X 阵列 -------- */
void NxDemo::createSolids()
{
    std::string name; int type, count; double a, b; bool notify;
    readValues(name, type, a, b, count, notify);

    if (a <= 0.0 || b <= 0.0 || a > kMaxDim || b > kMaxDim) {
        std::ostringstream os;
        os << "尺寸 A 和 B 必须大于 0 且不超过 " << kMaxDim << " mm。";
        theUI->NXMessageBox()->Show("输入错误", NXMessageBox::DialogTypeError, os.str().c_str());
        return;
    }
    if (count < 1) count = 1;
    if (count > 50) count = 50;

    WcsGuard wcsGuard;   /* UF_MODL_* 按 WCS 建模, 先临时切到绝对系 (坑账§4★) */

    double pitch = a * 1.5;
    double dir[3] = { 0.0, 0.0, 1.0 };
    int created = 0;

    for (int i = 0; i < count; ++i)
    {
        double org[3] = { i * pitch, 0.0, 0.0 };
        tag_t feat = NULL_TAG; int err = 0; char s1[64], s2[64];
        switch (type)
        {
        case TYPE_BLOCK: {
            char e1[64], e2[64], e3[64];
            snprintf(e1, sizeof e1, "%.4f", a);
            snprintf(e2, sizeof e2, "%.4f", b);
            snprintf(e3, sizeof e3, "%.4f", a * 0.6);
            char* edges[3] = { e1, e2, e3 };
            err = UF_MODL_create_block1(UF_NULLSIGN, org, edges, &feat);
            break; }
        case TYPE_CYLINDER:
            snprintf(s1, sizeof s1, "%.4f", b);   // height
            snprintf(s2, sizeof s2, "%.4f", a);   // diameter
            err = UF_MODL_create_cyl1(UF_NULLSIGN, org, s1, s2, dir, &feat);
            break;
        case TYPE_SPHERE:
            snprintf(s1, sizeof s1, "%.4f", a);   // diameter
            err = UF_MODL_create_sphere1(UF_NULLSIGN, org, s1, &feat);
            break;
        }
        if (err == 0 && feat != NULL_TAG) ++created;
    }

    if (notify) {
        const char* tn[3] = { "长方体", "圆柱体", "球体" };
        std::ostringstream os;
        os << "创建完成!\n  名称 : " << name
           << "\n  类型 : " << ((type>=0&&type<=2)?tn[type]:"图元")
           << "\n  数量 : " << created << " / " << count;
        theUI->NXMessageBox()->Show("完成", NXMessageBox::DialogTypeInformation, os.str().c_str());
    }
}

/* -------- 回调 -------- */
int NxDemo::apply_cb()
{
    try { createSolids(); }
    catch (const NXException& ex) { theUI->NXMessageBox()->Show("错误", NXMessageBox::DialogTypeError, ex.Message()); }
    catch (...)                   { theUI->NXMessageBox()->Show("错误", NXMessageBox::DialogTypeError, "发生未知错误。"); }
    return 0;
}
int NxDemo::ok_cb()     { apply_cb(); return 0; }
int NxDemo::cancel_cb() { return 0; }

int NxDemo::update_cb(NXOpen::BlockStyler::UIBlock* block)
{
    try { if (block == btn_preview) showParams(); }
    catch (const NXException& ex) { theUI->NXMessageBox()->Show("错误", NXMessageBox::DialogTypeError, ex.Message()); }
    return 0;
}

/* ============ NX 入口点 ============ */
extern "C" DllExport void ufusr(char* param, int* retcod, int parm_len)
{
    IkunUpdateReminder::CheckOnceOnFirstPluginUse();
    UF_initialize();
    try {
        std::string dlxPath = dlxPathBesideDll();   /* dll 同目录同名 .dlx, 免硬编码 */
        NxDemo* dlg = new NxDemo(dlxPath.c_str());
        dlg->Show();
        delete dlg;
    }
    catch (const NXException& ex) {
        UI::GetUI()->NXMessageBox()->Show("启动错误", NXMessageBox::DialogTypeError, ex.Message());
    }
    catch (...) {
        UI::GetUI()->NXMessageBox()->Show("启动错误", NXMessageBox::DialogTypeError, "发生未知错误。");
    }
    UF_terminate();
}

/* 立即卸载, 便于反复改了重新加载调试 */
extern "C" DllExport int ufusr_ask_unload(void) { return UF_UNLOAD_IMMEDIATELY; }
