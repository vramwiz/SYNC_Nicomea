unit SYNC_MusicStudio_DarkTheme;

// VCLフォームと共通操作部品へ、演奏スタジオ設定画面の暗色配色を適用する。

interface

uses
  System.Types,
  System.UITypes,
  Winapi.Messages,
  Winapi.Windows,
  Vcl.ComCtrls,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.StdCtrls;

type
  // ネイティブのチェック動作を使い、チェック欄と文字を暗色で描画する。
  TSyncMusicStudioDarkCheckBox = class(TCheckBox)
  private
    procedure PaintCheck(DC: HDC);
    procedure WMPaint(var Msg: TWMPaint); message WM_PAINT;
  protected
    procedure WndProc(var Msg: TMessage); override;
  end;

const
  SYNC_MUSIC_STUDIO_DARK_BACKGROUND_COLOR = TColor($00202020);
  SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR = TColor($00262626);
  SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR = TColor($00303030);
  SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR = TColor($00E6E6E6);

// フォーム本体とWindowsタイトルバーを暗色へ揃える。
procedure ApplySyncMusicStudioDarkForm(Form: TForm);
// フレームが親の明色背景を継承しないようにする。
procedure ApplySyncMusicStudioDarkFrame(Frame: TFrame);
// パネルの背景と文字色を揃える。
procedure ApplySyncMusicStudioDarkPanel(Panel: TPanel);
// 候補コンボを暗色の所有者描画に切り替える。
procedure ApplySyncMusicStudioDarkComboBox(ComboBox: TComboBox;
  DrawItemEvent: TDrawItemEvent);
// 文字入力欄の背景と文字色を揃える。
procedure ApplySyncMusicStudioDarkEdit(Edit: TEdit);
// 複数行入力欄の背景と文字色を揃える。
procedure ApplySyncMusicStudioDarkMemo(Memo: TMemo);
// 歌詞一覧の背景と文字色を揃える。
procedure ApplySyncMusicStudioDarkListBox(ListBox: TListBox);
// 配置要素一覧の背景と文字色を揃える。
procedure ApplySyncMusicStudioDarkListView(ListView: TListView);
// ボタンのVCL標準配色を暗色へ切り替える。
procedure ApplySyncMusicStudioDarkButton(Button: TButton);
// DPIに合わせた余白で候補コンボの1項目を描画する。
procedure DrawSyncMusicStudioDarkComboBoxItem(ComboBox: TComboBox;
  Index: Integer; const ItemRect: TRect; State: TOwnerDrawState;
  PPI: Integer);

implementation

uses
  System.Math,
  Winapi.Dwmapi,
  Winapi.UxTheme;

const
  DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 = 19;
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

procedure TSyncMusicStudioDarkCheckBox.PaintCheck(DC: HDC);
var
  Surface: TCanvas;
  Bounds, Box, TextBounds: TRect;
  Size, Top, SavedDC: Integer;
begin
  SavedDC := SaveDC(DC);
  if SavedDC = 0 then Exit;
  Surface := TCanvas.Create;
  try
    Surface.Handle := DC;
    Surface.Font.Assign(Font);
    Surface.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
    if not Enabled then Surface.Font.Color := $009C9C9C;
    Bounds := ClientRect;
    Surface.Brush.Color := SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR;
    Surface.FillRect(Bounds);
    Size := MulDiv(14, CurrentPPI, 96);
    Top := (Bounds.Height - Size) div 2;
    Box := Rect(1, Top, 1 + Size, Top + Size);
    Surface.Brush.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
    Surface.Pen.Color := $00848484;
    if Checked then Surface.Brush.Color := $00AE733C;
    Surface.Rectangle(Box);
    if Checked then
    begin
      Surface.Pen.Color := clWhite;
      Surface.Pen.Width := Max(1, MulDiv(2, CurrentPPI, 96));
      Surface.MoveTo(Box.Left + Size div 5, Box.Top + Size div 2);
      Surface.LineTo(Box.Left + Size * 2 div 5, Box.Top + Size * 3 div 4);
      Surface.LineTo(Box.Right - Size div 6, Box.Top + Size div 4);
    end;
    TextBounds := Bounds;
    TextBounds.Left := Box.Right + MulDiv(6, CurrentPPI, 96);
    SelectObject(DC, Surface.Font.Handle);
    SetTextColor(DC, ColorToRGB(Surface.Font.Color));
    SetBkMode(DC, TRANSPARENT);
    DrawText(DC, PChar(Caption), Length(Caption), TextBounds,
      DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
    if Focused then
    begin
      TextBounds.Right := Min(TextBounds.Right, TextBounds.Left + Surface.TextWidth(Caption) + 2);
      DrawFocusRect(DC, TextBounds);
    end;
  finally
    Surface.Handle := 0;
    Surface.Free;
    RestoreDC(DC, SavedDC);
  end;
end;

procedure TSyncMusicStudioDarkCheckBox.WMPaint(var Msg: TWMPaint);
var
  Paint: TPaintStruct;
  DC: HDC;
begin
  DC := Msg.DC;
  if DC <> 0 then
    PaintCheck(DC)
  else
  begin
    DC := BeginPaint(Handle, Paint);
    try
      PaintCheck(DC);
    finally
      EndPaint(Handle, Paint);
    end;
  end;
end;

procedure TSyncMusicStudioDarkCheckBox.WndProc(var Msg: TMessage);
begin
  if Msg.Msg = WM_PRINTCLIENT then
  begin
    PaintCheck(HDC(Msg.WParam));
    Exit;
  end;
  inherited;
  if Msg.Msg in [WM_SETFOCUS, WM_KILLFOCUS, WM_ENABLE] then Invalidate;
  if Msg.Msg = BM_SETCHECK then Invalidate;
end;

procedure EnableDarkTitleBar(Form: TForm);
var
  Enabled: BOOL;
begin
  Form.HandleNeeded;
  Enabled := True;
  if DwmSetWindowAttribute(Form.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE,
    @Enabled, SizeOf(Enabled)) <> S_OK then
    DwmSetWindowAttribute(Form.Handle,
      DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1, @Enabled,
      SizeOf(Enabled));
end;

procedure ApplySyncMusicStudioDarkForm(Form: TForm);
begin
  Form.Color := SYNC_MUSIC_STUDIO_DARK_BACKGROUND_COLOR;
  Form.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  EnableDarkTitleBar(Form);
end;

procedure ApplySyncMusicStudioDarkFrame(Frame: TFrame);
begin
  Frame.ParentBackground := False;
  Frame.ParentColor := False;
  Frame.ParentFont := False;
  Frame.Color := SYNC_MUSIC_STUDIO_DARK_BACKGROUND_COLOR;
  Frame.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
end;

procedure ApplySyncMusicStudioDarkPanel(Panel: TPanel);
begin
  Panel.ParentBackground := False;
  Panel.Color := SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR;
  Panel.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
end;

procedure ApplySyncMusicStudioDarkComboBox(ComboBox: TComboBox;
  DrawItemEvent: TDrawItemEvent);
begin
  ComboBox.Style := csOwnerDrawFixed;
  ComboBox.ItemHeight := MulDiv(16, ComboBox.CurrentPPI, 96);
  ComboBox.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  ComboBox.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  ComboBox.StyleElements := ComboBox.StyleElements - [seClient];
  ComboBox.OnDrawItem := DrawItemEvent;
  ComboBox.HandleNeeded;
  SetWindowTheme(ComboBox.Handle, 'DarkMode_CFD', nil);
end;

procedure ApplySyncMusicStudioDarkEdit(Edit: TEdit);
begin
  Edit.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  Edit.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  Edit.StyleElements := Edit.StyleElements - [seClient];
end;

procedure ApplySyncMusicStudioDarkMemo(Memo: TMemo);
begin
  Memo.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  Memo.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  Memo.StyleElements := Memo.StyleElements - [seClient];
end;

procedure ApplySyncMusicStudioDarkListBox(ListBox: TListBox);
begin
  ListBox.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  ListBox.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  ListBox.StyleElements := ListBox.StyleElements - [seClient];
  ListBox.HandleNeeded;
  SetWindowTheme(ListBox.Handle, 'DarkMode_Explorer', nil);
end;

procedure ApplySyncMusicStudioDarkListView(ListView: TListView);
begin
  ListView.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  ListView.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  ListView.StyleElements := ListView.StyleElements - [seClient];
  ListView.HandleNeeded;
  SetWindowTheme(ListView.Handle, 'DarkMode_Explorer', nil);
end;

procedure ApplySyncMusicStudioDarkButton(Button: TButton);
begin
  Button.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  Button.HandleNeeded;
  SetWindowTheme(Button.Handle, 'DarkMode_Explorer', nil);
end;

procedure DrawSyncMusicStudioDarkComboBoxItem(ComboBox: TComboBox;
  Index: Integer; const ItemRect: TRect; State: TOwnerDrawState;
  PPI: Integer);
var
  DrawRect: TRect;
  Text: string;
begin
  if odSelected in State then
  begin
    ComboBox.Canvas.Brush.Color := clHighlight;
    ComboBox.Canvas.Font.Color := clHighlightText;
  end
  else
  begin
    ComboBox.Canvas.Brush.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
    ComboBox.Canvas.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  end;
  ComboBox.Canvas.FillRect(ItemRect);
  if (Index < 0) or (Index >= ComboBox.Items.Count) then
    Exit;

  Text := ComboBox.Items[Index];
  DrawRect := ItemRect;
  Inc(DrawRect.Left, MulDiv(4, PPI, 96));
  DrawText(ComboBox.Canvas.Handle, PChar(Text), Length(Text), DrawRect,
    DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

end.
