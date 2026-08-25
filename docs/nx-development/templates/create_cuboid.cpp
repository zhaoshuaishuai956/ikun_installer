/* ============================================================
 *  create_cuboid.cpp  -  创建长方体 (Block Styler)
 *  NX 1847, ExpressionBlock, 无内部按钮
 *  入口: ufusr (Ctrl+U 加载 dll)
 * ============================================================ */
#include <windows.h>
#ifdef CreateDialog
#undef CreateDialog
#endif
#ifdef max
#undef max
#endif
#ifdef min
#undef min
#endif
#include <uf.h>
#include <uf_modl.h>
#include <uf_csys.h>
#include "create_cuboid.hpp"
#include "build_sha.h"   /* M14: 构建 SHA 由 build.ps1 生成 (CI G8 比对用) */
#include "ikun_update_check.hpp"
#include <sstream>
#include <cstdio>

using namespace NXOpen;
using namespace NXOpen::BlockStyler;

NXOpen::Session *CreateCuboid::theSession = NULL;
NXOpen::UI      *CreateCuboid::theUI      = NULL;

/* 尺寸上限(mm)：防超大输入撑爆 snprintf 缓冲/生成病态几何 */
static const double kMaxDim = 100000.0;

/* WcsGuard: UF_MODL_* 图元按当前 WCS 定位，操作期间临时切绝对系，
 * 离开(含异常)自动还原 (坑账§4★) */
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

CreateCuboid::CreateCuboid(const char* dlxPath)
{
    theSession = Session::GetSession();
    theUI      = UI::GetUI();
    theDlxFileName = dlxPath;
    theDialog = theUI->CreateDialog(theDlxFileName.c_str());
    theDialog->AddInitializeHandler(make_callback(this, &CreateCuboid::init_cb));
    theDialog->AddApplyHandler     (make_callback(this, &CreateCuboid::apply_cb));
    theDialog->AddOkHandler        (make_callback(this, &CreateCuboid::ok_cb));
    theDialog->AddCancelHandler    (make_callback(this, &CreateCuboid::cancel_cb));
    theDialog->AddUpdateHandler    (make_callback(this, &CreateCuboid::update_cb));
}
CreateCuboid::~CreateCuboid() { if (theDialog) { delete theDialog; theDialog = NULL; } }
void CreateCuboid::Show() { theDialog->Show(); }

void CreateCuboid::init_cb()
{
    CompositeBlock* top = theDialog->TopBlock();
    lbl_info = dynamic_cast<Label*>          (top->FindBlock("LBL_INFO"));
    expr_len = dynamic_cast<ExpressionBlock*>(top->FindBlock("DBL_LEN"));
}

double CreateCuboid::readLength()
{
    if (!expr_len) return 100.0;
    return expr_len->Value();
}

void CreateCuboid::createCuboid()
{
    double len = readLength();
    if (len <= 0.0 || len > kMaxDim)
    {
        theUI->NXMessageBox()->Show("input error", NXMessageBox::DialogTypeError,
                                    "len must be > 0 and <= 100000 mm");
        return;
    }
    WcsGuard wcsGuard;   /* UF_MODL_* 按 WCS 建模，先临时切绝对系 (坑账§4★) */
    double org[3] = { 0.0, 0.0, 0.0 };
    char e1[64], e2[64], e3[64];
    snprintf(e1, sizeof e1, "%.4f", len);
    snprintf(e2, sizeof e2, "%.4f", len);
    snprintf(e3, sizeof e3, "%.4f", len);
    char* edges[3] = { e1, e2, e3 };
    tag_t feat = NULL_TAG;
    int err = UF_MODL_create_block1(UF_NULLSIGN, org, edges, &feat);
    if (err == 0 && feat != NULL_TAG)
    {
        std::ostringstream os;
        os << "Block created, len=" << len << " mm";
        theUI->NXMessageBox()->Show("OK", NXMessageBox::DialogTypeInformation, os.str().c_str());
    }
    else
    {
        theUI->NXMessageBox()->Show("error", NXMessageBox::DialogTypeError, "create block failed");
    }
}

int CreateCuboid::apply_cb()
{
    try { createCuboid(); }
    catch (const NXException& ex) { theUI->NXMessageBox()->Show("error", NXMessageBox::DialogTypeError, ex.Message()); }
    catch (...)                   { theUI->NXMessageBox()->Show("error", NXMessageBox::DialogTypeError, "unknown error"); }
    return 0;
}
int CreateCuboid::ok_cb()     { apply_cb(); return 0; }
int CreateCuboid::cancel_cb() { return 0; }
int CreateCuboid::update_cb(NXOpen::BlockStyler::UIBlock* block) { return 0; }

extern "C" DllExport void ufusr(char* param, int* retcod, int parm_len)
{
    IkunUpdateReminder::CheckOnceOnFirstPluginUse();
    UF_initialize();
    try {
        char dlxPath[MAX_PATH] = "";
        HMODULE hm = NULL;
        GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          (LPCSTR)&ufusr, &hm);
        if (hm)
        {
            GetModuleFileNameA(hm, dlxPath, MAX_PATH);
            char* lastSep = strrchr((char*)dlxPath, '\\');
            if (lastSep) *lastSep = '\0';
            strcat_s(dlxPath, MAX_PATH, "\\create_cuboid.dlx");
        }
        CreateCuboid* dlg = new CreateCuboid(dlxPath);
        dlg->Show();
        delete dlg;
    }
    catch (const NXException& ex) {
        UI::GetUI()->NXMessageBox()->Show("startup error", NXMessageBox::DialogTypeError, ex.Message());
    }
    catch (...) {
        UI::GetUI()->NXMessageBox()->Show("startup error", NXMessageBox::DialogTypeError, "unknown error");
    }
    UF_terminate();
}

extern "C" DllExport int ufusr_ask_unload(void) { return UF_UNLOAD_IMMEDIATELY; }
