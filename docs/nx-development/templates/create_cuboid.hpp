/* ============================================================
 *  create_cuboid.hpp  -  创建长方体 (Block Styler 对话框)
 *  NX 1847, ExpressionBlock数值输入, 无内部按钮
 * ============================================================ */
#ifndef CREATE_CUBOID_HPP_INCLUDED
#define CREATE_CUBOID_HPP_INCLUDED

#include <uf_defs.h>
#include <NXOpen/Session.hxx>
#include <NXOpen/UI.hxx>
#include <NXOpen/NXMessageBox.hxx>
#include <NXOpen/Callback.hxx>
#include <NXOpen/NXException.hxx>
#include <NXOpen/NXString.hxx>
#include <NXOpen/BlockStyler_UIBlock.hxx>
#include <NXOpen/BlockStyler_CompositeBlock.hxx>
#include <NXOpen/BlockStyler_BlockDialog.hxx>
#include <NXOpen/BlockStyler_PropertyList.hxx>
#include <NXOpen/BlockStyler_Label.hxx>
#include <NXOpen/BlockStyler_ExpressionBlock.hxx>

class CreateCuboid
{
public:
    static NXOpen::Session *theSession;
    static NXOpen::UI      *theUI;

    CreateCuboid(const char* dlxPath);
    ~CreateCuboid();
    void Show();

    void init_cb();
    int  apply_cb();
    int  ok_cb();
    int  cancel_cb();
    int  update_cb(NXOpen::BlockStyler::UIBlock* block);

private:
    double readLength();
    void   createCuboid();

    NXOpen::BlockStyler::BlockDialog    *theDialog;
    std::string theDlxFileName;

    NXOpen::BlockStyler::Label          *lbl_info;
    NXOpen::BlockStyler::ExpressionBlock *expr_len;   // 边长: ExpressionBlock, 可键入公式/单位
};

#endif
