/* ============================================================
 *  {{NAME}}.hpp  -  NX 二次开发 Block Styler 对话框 (NX 1847)
 *  由 nx-blockstyler-dev skill 生成的模板。把 {{NAME}} 替换为
 *  你的工程名, 按需增删控件指针与回调。
 * ============================================================ */
#ifndef NX_DEMO_HPP_INCLUDED
#define NX_DEMO_HPP_INCLUDED

#include <uf_defs.h>
#include <NXOpen/Session.hxx>
#include <NXOpen/UI.hxx>
#include <NXOpen/NXMessageBox.hxx>
#include <NXOpen/Callback.hxx>
#include <NXOpen/NXException.hxx>
#include <NXOpen/NXString.hxx>
#include <NXOpen/BlockStyler_UIBlock.hxx>
#include <NXOpen/BlockStyler_CompositeBlock.hxx>   // TopBlock() 返回它, FindBlock 在它上面
#include <NXOpen/BlockStyler_BlockDialog.hxx>
#include <NXOpen/BlockStyler_PropertyList.hxx>
#include <NXOpen/BlockStyler_Group.hxx>
#include <NXOpen/BlockStyler_Label.hxx>
#include <NXOpen/BlockStyler_StringBlock.hxx>
#include <NXOpen/BlockStyler_Enumeration.hxx>
#include <NXOpen/BlockStyler_ExpressionBlock.hxx>
#include <NXOpen/BlockStyler_IntegerBlock.hxx>      // 类名是 IntegerBlock, 不是 IntBlock
#include <NXOpen/BlockStyler_Toggle.hxx>
#include <NXOpen/BlockStyler_Button.hxx>
#include <string>

class NxDemo
{
public:
    static NXOpen::Session *theSession;
    static NXOpen::UI      *theUI;

    NxDemo(const char* dlxPath);
    ~NxDemo();
    void Show();

    // Block Styler 标准回调 (注意 init 返回 void)
    void init_cb();
    int  apply_cb();
    int  ok_cb();
    int  cancel_cb();
    int  update_cb(NXOpen::BlockStyler::UIBlock* block);

private:
    void readValues(std::string& name, int& type,
                    double& a, double& b, int& count, bool& notify);
    void createSolids();
    void showParams();

    NXOpen::BlockStyler::BlockDialog *theDialog = nullptr;
    std::string theDlxFileName;

    // 控件指针默认 nullptr; init_cb 里 FindBlock 绑定, 找不到保持空(读值处已判空)
    NXOpen::BlockStyler::Group           *group_main  = nullptr;
    NXOpen::BlockStyler::Label           *lbl_info    = nullptr;
    NXOpen::BlockStyler::StringBlock     *str_name    = nullptr;
    NXOpen::BlockStyler::Enumeration     *enum_type   = nullptr;
    NXOpen::BlockStyler::ExpressionBlock *expr_a      = nullptr;   // 数值输入用表达式块 (坑账§2)
    NXOpen::BlockStyler::ExpressionBlock *expr_b      = nullptr;
    NXOpen::BlockStyler::IntegerBlock    *int_count   = nullptr;
    NXOpen::BlockStyler::Toggle          *tgl_notify  = nullptr;
    NXOpen::BlockStyler::Button          *btn_preview = nullptr;
};

#endif
