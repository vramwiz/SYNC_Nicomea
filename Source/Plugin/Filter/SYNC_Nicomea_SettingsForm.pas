unit SYNC_Nicomea_SettingsForm;

// AviUtl2の背景プレビューを流用し、相対領域と文字装飾を編集中だけ変更する。
interface

uses
  System.Classes, System.Types, Vcl.ComCtrls, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics,
  Vcl.StdCtrls, SYNC_LipSync_PreviewViewport, SYNC_MusicStudio_HostBackground,
  SYNC_Nicomea_History, SYNC_Nicomea_Layout, SYNC_Nicomea_Renderer,
  ColorPickerHueBar, ColorPickerSVArea;

type
  TFormNicomeaSettings = class(TForm)
  private type
    TDragMode = (dmNone, dmPan, dmMove, dmResize, dmOutline, dmShadow, dmBlur);
    TDecorationMode = dmOutline..dmBlur;
    TColorTarget = (ctText, ctOutline, ctShadow);
  private
    FPreview, FDecorationSample: TPaintBox;
    FSettingsScroll: TScrollBox;
    FBackground, FBuffer, FDecorationBuffer: TBitmap;
    FTimer: TTimer;
    FReadBackground: TMusicStudioReadBackground;
    FSerial: UInt64;
    FFrameWidth, FFrameHeight: Integer;
    FViewport: TLipSyncPreviewViewport;
    FRenderer, FDecorationRenderer: TNicomeaRenderer;
    FLayout: TNicomeaLayout;
    FSupporters: TArray<TNicomeaSupporter>;
    FSupportersByKind: TNicomeaSupportersByKind;
    FKind: TNicomeaHistoryKind;
    FStyle, FFont, FKindSelector, FEffect: TComboBox;
    FFormat, FSeparator: TEdit;
    FSize, FSpacing, FLineGap: TTrackBar;
    FBold, FItalic, FOutline, FShadow: TButton;
    FColorButtons: array[TColorTarget] of TButton;
    FHueBar: TColorPickerHueBar;
    FColorArea: TColorPickerSVArea;
    FColorSwatch: TPanel;
    FColorTarget: TColorTarget;
    FSingleColumn: TCheckBox;
    FHint: TLabel;
    FPreviewSource: string;
    FUpdating, FDirty, FDecorationDirty, FPlaying, FSelected: Boolean;
    FDuration, FPausedProgress: Double;
    FPlayStart: UInt64;
    FDragMode: TDragMode;
    FDragControl: TControl;
    FDragButton: TMouseButton;
    FDragMoved: Boolean;
    FDragGrip: Integer;
    FDragStart, FDragLast: TPoint;
    FDragLayout: TNicomeaLayout;
    procedure BuildControls(Panel: TPanel);
    procedure FitToWorkArea;
    procedure SyncControls;
    procedure SyncFormatControls;
    procedure BuildFormatMenu;
    procedure InsertFormatToken(Sender: TObject);
    procedure KindChanged(Sender: TObject);
    procedure FormatChanged(Sender: TObject);
    procedure ReadControls(Sender: TObject);
    procedure StyleChanged(Sender: TObject);
    procedure ResetStyle(Sender: TObject);
    procedure ToggleDecoration(Sender: TObject);
    function TargetColor: TColor;
    procedure SyncColorPicker;
    procedure SelectColorTarget(Sender: TObject);
    procedure HueChanged(Sender: TObject);
    procedure ColorChanged(Sender: TObject);
    procedure UpdatePreviewCaption;
    procedure TogglePlayback;
    procedure DrawCombo(Control: TWinControl; Index: Integer; Bounds: TRect; State: TOwnerDrawState);
    function Progress: Double;
    function FitRect: TRect;
    function PreviewArea(const Frame: TRect): TRect;
    function DecorationHandle(Mode: TDecorationMode): TRect;
    function DecorationEnabled(Mode: TDecorationMode): Boolean;
    function DecorationAt(const CursorPoint: TPoint): TDragMode;
    procedure InvalidateDecorationSample;
    procedure PaintDecorationSample(Sender: TObject);
    procedure RefreshBackground;
    procedure PreviewTick(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure PreviewWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure EditMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure EditMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure EditMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure UpdateDrag(X, Y: Integer);
  protected
    procedure DoShow; override;
    procedure DoAfterMonitorDpiChanged(OldDPI, NewDPI: Integer); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 呼び出し側の設定はコピーする。OK後だけLayoutを読み出す。
    procedure LoadLayout(const Layout: TNicomeaLayout;
      const Supporters: TNicomeaSupportersByKind; Kind: TNicomeaHistoryKind;
      Width, Height: Integer; Duration: Double; ReadBackground: TMusicStudioReadBackground);
    property Layout: TNicomeaLayout read FLayout;
    property Kind: TNicomeaHistoryKind read FKind;
  end;

implementation

uses
  System.Math, System.SysUtils, System.UITypes, Winapi.GDIPAPI, Winapi.GDIPOBJ, Winapi.Messages,
  Winapi.UxTheme, Winapi.Windows, Vcl.Menus, SYNC_MusicStudio_DarkTheme, ColorPickerColorMath;

const
  MUTED_TEXT = TColor($00B5B5B5);
  BUTTON_BORDER = TColor($00545454);
  BUTTON_ACCENT = TColor($006D492B);
  ACCENT_BORDER = TColor($00D6A778);
  STYLE_NAMES: array[TNicomeaStyle] of string = ('横スクロール', '縦スクロール', 'ページ切り替え');
  EFFECT_NAMES: array[TNicomeaEffect] of string = ('なし', 'フェード');
  SETTINGS_WIDTH = 752;
  SETTINGS_HEIGHT = 160;
  DEFAULT_CLIENT_WIDTH = 804;
  DEFAULT_CLIENT_HEIGHT = 640;
  MIN_FORM_WIDTH = SETTINGS_WIDTH + 40;
  MIN_FORM_HEIGHT = 360;

type
  TNicomeaDarkButton = class(TButton)
  private
    FAccent: Boolean;
    procedure DrawButton(var Message: TWMDrawItem); message CN_DRAWITEM;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure SetButtonStyle(ADefault: Boolean); override;
  end;

procedure TNicomeaDarkButton.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := Params.Style or BS_OWNERDRAW;
end;

procedure TNicomeaDarkButton.SetButtonStyle(ADefault: Boolean);
begin
  Invalidate;
end;

procedure TNicomeaDarkButton.DrawButton(var Message: TWMDrawItem);
var
  Item: PDrawItemStruct;
  Bounds: TRect;
  FillColor, BorderColor: TColor;
  Brush: HBRUSH;
  SavedDC: Integer;
begin
  Item := Message.DrawItemStruct;
  Bounds := Item^.rcItem;
  FillColor := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  BorderColor := BUTTON_BORDER;
  if FAccent then
  begin
    FillColor := BUTTON_ACCENT;
    BorderColor := ACCENT_BORDER;
  end;
  if Item^.itemState and ODS_SELECTED <> 0 then
    FillColor := SYNC_MUSIC_STUDIO_DARK_BACKGROUND_COLOR;
  SavedDC := SaveDC(Item^.hDC);
  try
    Brush := GetStockObject(DC_BRUSH);
    SetDCBrushColor(Item^.hDC, ColorToRGB(FillColor));
    FillRect(Item^.hDC, Bounds, Brush);
    SetDCBrushColor(Item^.hDC, ColorToRGB(BorderColor));
    FrameRect(Item^.hDC, Bounds, Brush);
    SelectObject(Item^.hDC, Font.Handle);
    SetBkMode(Item^.hDC, TRANSPARENT);
    SetTextColor(Item^.hDC, ColorToRGB(SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR));
    DrawText(Item^.hDC, PChar(Caption), -1, Bounds, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    if Item^.itemState and ODS_FOCUS <> 0 then
    begin
      InflateRect(Bounds, -3, -3);
      DrawFocusRect(Item^.hDC, Bounds);
    end;
  finally
    RestoreDC(Item^.hDC, SavedDC);
  end;
  Message.Result := 1;
end;

function DarkPanel(Parent: TWinControl; Alignment: TAlign): TPanel;
begin
  Result := TPanel.Create(Parent);
  Result.Parent := Parent;
  Result.BevelOuter := bvNone;
  Result.Top := Parent.ClientHeight;
  Result.Align := Alignment;
  Result.StyleElements := [];
  ApplySyncMusicStudioDarkPanel(Result);
end;

function LabelAt(Parent: TWinControl; const Text: string; X, Y: Integer): TLabel;
begin
  Result := TLabel.Create(Parent);
  Result.Parent := Parent;
  Result.Caption := Text;
  Result.ShowAccelChar := False;
  Result.Left := X;
  Result.Top := Y;
end;

function ButtonAt(Parent: TWinControl; const Text: string;
  X, Y, W: Integer; Click: TNotifyEvent = nil): TNicomeaDarkButton;
begin
  Result := TNicomeaDarkButton.Create(Parent);
  Result.Parent := Parent;
  Result.Caption := Text;
  Result.SetBounds(X, Y, W, 30);
  Result.OnClick := Click;
end;

procedure AddDialogButtons(Form: TForm);
var
  Footer: TPanel;
  Button: TNicomeaDarkButton;
begin
  Footer := DarkPanel(Form, alBottom);
  Footer.Color := Form.Color;
  Footer.Height := 42;
  Footer.Padding.Top := 8;
  Button := ButtonAt(Footer, 'キャンセル', 0, 0, 104);
  Button.Align := alRight;
  Button.Cancel := True;
  Button.ModalResult := mrCancel;
  Button := ButtonAt(Footer, 'OK', 0, 0, 82);
  Button.Align := alRight;
  Button.AlignWithMargins := True;
  Button.Margins.SetBounds(0, 0, 8, 0);
  Button.ModalResult := mrOk;
  Button.Default := True;
  Button.FAccent := True;
end;

constructor TFormNicomeaSettings.Create(AOwner: TComponent);
var
  SettingsPanel, PreviewPanel: TPanel;
  PreviewMenu: TPopupMenu;
  ResetItem: TMenuItem;
begin
  inherited CreateNew(AOwner);
  Caption := 'ニコメアの設定';
  Position := poScreenCenter;
  ClientWidth := DEFAULT_CLIENT_WIDTH;
  ClientHeight := DEFAULT_CLIENT_HEIGHT;
  Padding.SetBounds(12, 12, 12, 12);
  // 手動配置とフォントを96 DPIで揃えてから、フォーム全体を拡大する。
  Font.PixelsPerInch := USER_DEFAULT_SCREEN_DPI;
  Font.IsDPIRelated := True;
  Font.Name := 'Yu Gothic UI';
  Font.Size := 10;
  StyleElements := [];
  DoubleBuffered := True;
  OnMouseWheel := PreviewWheel;
  ApplySyncMusicStudioDarkForm(Self);
  FBackground := Vcl.Graphics.TBitmap.Create;
  FBuffer := Vcl.Graphics.TBitmap.Create;
  FDecorationBuffer := Vcl.Graphics.TBitmap.Create;
  FRenderer := TNicomeaRenderer.Create;
  FDecorationRenderer := TNicomeaRenderer.Create;
  AddDialogButtons(Self);

  FSettingsScroll := TScrollBox.Create(Self);
  FSettingsScroll.Parent := Self;
  FSettingsScroll.Height := SETTINGS_HEIGHT;
  FSettingsScroll.Align := alBottom;
  FSettingsScroll.AlignWithMargins := True;
  FSettingsScroll.Margins.SetBounds(0, 8, 0, 0);
  FSettingsScroll.BorderStyle := bsNone;
  FSettingsScroll.Color := SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR;
  SettingsPanel := DarkPanel(FSettingsScroll, alNone);
  SettingsPanel.SetBounds(0, 0, SETTINGS_WIDTH, SETTINGS_HEIGHT);
  BuildControls(SettingsPanel);

  PreviewPanel := DarkPanel(Self, alClient);
  PreviewPanel.Padding.SetBounds(10, 8, 10, 10);
  FHint := LabelAt(PreviewPanel, '', 0, 0);
  FHint.Align := alTop;
  FHint.AutoSize := False;
  FHint.Height := 25;
  FHint.Font.Color := MUTED_TEXT;
  FHint.EllipsisPosition := epEndEllipsis;
  FPreview := TPaintBox.Create(Self);
  FPreview.Parent := PreviewPanel;
  FPreview.Align := alClient;
  FPreview.Hint := '左クリックで一時停止・再生、右クリックで配置を初期化' + sLineBreak +
    'ホイールで拡大、中ドラッグで移動';
  FPreview.ShowHint := True;
  FPreview.OnPaint := PaintPreview;
  FPreview.OnMouseDown := EditMouseDown;
  FPreview.OnMouseMove := EditMouseMove;
  FPreview.OnMouseUp := EditMouseUp;
  PreviewMenu := TPopupMenu.Create(Self);
  ResetItem := TMenuItem.Create(PreviewMenu);
  ResetItem.Caption := '配置を初期化';
  ResetItem.OnClick := ResetStyle;
  PreviewMenu.Items.Add(ResetItem);
  FPreview.PopupMenu := PreviewMenu;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 33;
  FTimer.OnTimer := PreviewTick;

  DisableAlign;
  try
    ScaleForPPI(CurrentPPI);
    ClientWidth := ScaleValue(DEFAULT_CLIENT_WIDTH);
    ClientHeight := ScaleValue(DEFAULT_CLIENT_HEIGHT);
  finally
    EnableAlign;
  end;
end;

procedure TFormNicomeaSettings.FitToWorkArea;
var
  Area: TRect;
  FitWidth, FitHeight: Integer;
begin
  Area := Monitor.WorkareaRect;
  Constraints.MinWidth := Min(ScaleValue(MIN_FORM_WIDTH), Area.Width);
  Constraints.MinHeight := Min(ScaleValue(MIN_FORM_HEIGHT), Area.Height);
  if WindowState <> wsNormal then Exit;
  FitWidth := Min(Width, Area.Width);
  FitHeight := Min(Height, Area.Height);
  SetBounds(EnsureRange(Left, Area.Left, Area.Right - FitWidth),
    EnsureRange(Top, Area.Top, Area.Bottom - FitHeight), FitWidth, FitHeight);
end;

procedure TFormNicomeaSettings.DoShow;
begin
  FitToWorkArea;
  inherited;
end;

procedure TFormNicomeaSettings.DoAfterMonitorDpiChanged(OldDPI, NewDPI: Integer);
begin
  inherited;
  FitToWorkArea;
end;

procedure TFormNicomeaSettings.Resize;
var
  SettingsHeight: Integer;
begin
  if (FSettingsScroll <> nil) and not (csDestroying in ComponentState) then
  begin
    SettingsHeight := ScaleValue(SETTINGS_HEIGHT);
    if ClientWidth - Padding.Left - Padding.Right < ScaleValue(SETTINGS_WIDTH) then
      Inc(SettingsHeight, ScaleValue(20));
    // 作業領域が狭い場合はプレビューの高さを確保し、設定側をスクロールする。
    FSettingsScroll.Height := Min(SettingsHeight, Max(0, ClientHeight - ScaleValue(180)));
  end;
  inherited;
end;

destructor TFormNicomeaSettings.Destroy;
begin
  if FTimer <> nil then FTimer.Enabled := False;
  FDecorationRenderer.Free;
  FRenderer.Free;
  FDecorationBuffer.Free;
  FBuffer.Free;
  FBackground.Free;
  inherited;
end;

procedure TFormNicomeaSettings.BuildControls(Panel: TPanel);
const
  ColorCaptions: array[TColorTarget] of string = ('文字', '縁', '影');
  ColorHints: array[TColorTarget] of string = ('文字の色', '縁取りの色', '影の色');
  MainLeft = 12;
  TextLeft = 268;
  ColorLeft = 528;
  TopRow = 8;
  MiddleRow = 56;
  BottomRow = 104;
  FieldOffset = 20;
  FieldHeight = 26;
  PickerTop = 44;
  PickerSize = 100;
  PickerGap = 6;
  HueWidth = 18;
  HueLeft = ColorLeft + PickerSize + PickerGap;
  SampleLeft = HueLeft + HueWidth + PickerGap;
  ColorRight = SETTINGS_WIDTH - 12;
var
  Style: TNicomeaStyle;
  Kind: TNicomeaHistoryKind;
  Effect: TNicomeaEffect;
  Target: TColorTarget;

  function Slider(const Text: string; X, Y, Width, MinValue, MaxValue: Integer): TTrackBar;
  begin
    LabelAt(Panel, Text, X, Y);
    Result := TTrackBar.Create(Panel);
    Result.Parent := Panel;
    Result.SetBounds(X, Y + FieldOffset, Width, FieldHeight);
    Result.Max := MaxValue;
    Result.Min := MinValue;
    Result.TickStyle := tsNone;
    Result.ShowSelRange := False;
    Result.PositionToolTip := ptTop;
    Result.PageSize := 1;
    Result.StyleElements := [];
    SetWindowTheme(Result.Handle, 'DarkMode_Explorer', nil);
    Result.OnChange := ReadControls;
  end;

  function Choice(const Text: string; X, Y, Width: Integer): TComboBox;
  begin
    LabelAt(Panel, Text, X, Y);
    Result := TComboBox.Create(Panel);
    Result.Parent := Panel;
    Result.SetBounds(X, Y + FieldOffset, Width, FieldHeight);
    ApplySyncMusicStudioDarkComboBox(Result, DrawCombo);
  end;

begin
  FStyle := Choice('表示スタイル', MainLeft, TopRow, 122);
  for Style := Low(TNicomeaStyle) to High(TNicomeaStyle) do FStyle.Items.Add(STYLE_NAMES[Style]);
  FStyle.OnChange := StyleChanged;

  FKindSelector := Choice('表示対象', MainLeft + 130, TopRow, 110);
  for Kind := Low(TNicomeaHistoryKind) to High(TNicomeaHistoryKind) do
    FKindSelector.Items.Add(NICOMEA_KIND_NAMES[Kind]);
  FKindSelector.OnChange := KindChanged;

  FEffect := Choice('演出', MainLeft, MiddleRow, 122);
  for Effect := Low(TNicomeaEffect) to High(TNicomeaEffect) do
    FEffect.Items.Add(EFFECT_NAMES[Effect]);
  FEffect.OnChange := ReadControls;

  FSingleColumn := TSyncMusicStudioDarkCheckBox.Create(Panel);
  FSingleColumn.Parent := Panel;
  FSingleColumn.SetBounds(MainLeft + 130, MiddleRow + FieldOffset, 110, FieldHeight);
  FSingleColumn.Caption := '1 列に並べる';
  FSingleColumn.OnClick := ReadControls;

  LabelAt(Panel, '書式（右クリックで挿入）', MainLeft, BottomRow);
  FFormat := TEdit.Create(Panel);
  FFormat.Parent := Panel;
  FFormat.SetBounds(MainLeft, BottomRow + FieldOffset, 176, FieldHeight);
  ApplySyncMusicStudioDarkEdit(FFormat);
  FFormat.PopupMenu := TPopupMenu.Create(FFormat);
  FFormat.OnChange := FormatChanged;

  LabelAt(Panel, '区切り', MainLeft + 184, BottomRow);
  FSeparator := TEdit.Create(Panel);
  FSeparator.Parent := Panel;
  FSeparator.SetBounds(MainLeft + 184, BottomRow + FieldOffset, 56, FieldHeight);
  ApplySyncMusicStudioDarkEdit(FSeparator);
  FSeparator.OnChange := ReadControls;

  FFont := Choice('フォント', TextLeft, TopRow, 138);
  FFont.DropDownWidth := 220;
  FFont.Items.Assign(Screen.Fonts);
  FFont.OnChange := ReadControls;
  FSize := Slider('文字サイズ', TextLeft + 146, TopRow, 98, 6, 256);
  FSpacing := Slider('文字間隔', TextLeft, MiddleRow, 118, 0, 64);
  FLineGap := Slider('行間', TextLeft + 126, MiddleRow, 118, 0, 128);

  FBold := ButtonAt(Panel, 'B', TextLeft, BottomRow + 16, 55, ToggleDecoration);
  FItalic := ButtonAt(Panel, 'I', TextLeft + 63, BottomRow + 16, 55, ToggleDecoration);
  FOutline := ButtonAt(Panel, '縁取り', TextLeft + 126, BottomRow + 16, 55, ToggleDecoration);
  FShadow := ButtonAt(Panel, '影', TextLeft + 189, BottomRow + 16, 55, ToggleDecoration);
  FBold.Font.Style := [fsBold];
  FItalic.Font.Style := [fsItalic];

  for Target := Low(TColorTarget) to High(TColorTarget) do
  begin
    FColorButtons[Target] := ButtonAt(Panel, ColorCaptions[Target],
      ColorLeft + Ord(Target) * 40, TopRow, 34, SelectColorTarget);
    FColorButtons[Target].Tag := Ord(Target);
    FColorButtons[Target].Hint := ColorHints[Target];
    FColorButtons[Target].ShowHint := True;
  end;
  FColorSwatch := DarkPanel(Panel, alNone);
  FColorSwatch.SetBounds(ColorLeft + 120, TopRow + 3, ColorRight - ColorLeft - 120, 24);

  FColorArea := TColorPickerSVArea.Create(Panel);
  FColorArea.Parent := Panel;
  FColorArea.SetBounds(ColorLeft, PickerTop, PickerSize, PickerSize);
  FColorArea.OnChange := ColorChanged;

  FHueBar := TColorPickerHueBar.Create(Panel);
  FHueBar.Parent := Panel;
  FHueBar.SetBounds(HueLeft, PickerTop, HueWidth, PickerSize);
  FHueBar.OnChange := HueChanged;

  FDecorationSample := TPaintBox.Create(Panel);
  FDecorationSample.Parent := Panel;
  FDecorationSample.SetBounds(SampleLeft, PickerTop, ColorRight - SampleLeft, PickerSize);
  FDecorationSample.ShowHint := True;
  FDecorationSample.OnPaint := PaintDecorationSample;
  FDecorationSample.OnMouseDown := EditMouseDown;
  FDecorationSample.OnMouseMove := EditMouseMove;
  FDecorationSample.OnMouseUp := EditMouseUp;
end;

procedure TFormNicomeaSettings.LoadLayout(const Layout: TNicomeaLayout;
  const Supporters: TNicomeaSupportersByKind; Kind: TNicomeaHistoryKind;
  Width, Height: Integer; Duration: Double; ReadBackground: TMusicStudioReadBackground);
begin
  FLayout := Layout;
  FSupportersByKind := Supporters;
  FKind := Kind;
  FFrameWidth := Width;
  FFrameHeight := Height;
  FDuration := Max(0.1, Duration);
  FReadBackground := ReadBackground;
  FSelected := True;
  FPlaying := True;
  FPausedProgress := 0;
  FPlayStart := GetTickCount64;
  SyncFormatControls;
  SyncColorPicker;
  SyncControls;
  PreviewTick(nil);
  FTimer.Enabled := True;
end;

procedure TFormNicomeaSettings.SyncFormatControls;
begin
  FUpdating := True;
  try
    FKindSelector.ItemIndex := Ord(FKind);
    FFormat.Text := FLayout.Formats[FKind];
    FSeparator.Text := FLayout.Separator;
  finally
    FUpdating := False;
  end;
  BuildFormatMenu;
  FSupporters := FSupportersByKind[FKind];
  FPreviewSource := NICOMEA_KIND_NAMES[FKind];
  if Length(FSupporters) = 0 then
  begin
    FSupporters := SampleNicomeaSupporters;
    FPreviewSource := FPreviewSource + '（サンプル）';
  end;
  UpdatePreviewCaption;
  FDirty := True;
  InvalidateDecorationSample;
end;

procedure TFormNicomeaSettings.BuildFormatMenu;
type
  TFormatToken = record
    Code: Char;
    Caption: string;
    Kinds: set of TNicomeaHistoryKind;
  end;
const
  Tokens: array[0..9] of TFormatToken = (
    (Code: 'n'; Caption: 'ユーザー名'; Kinds: [nhAdvertising, nhGifts]),
    (Code: 'p'; Caption: 'ポイント合計'; Kinds: [nhAdvertising, nhGifts]),
    (Code: 'r'; Caption: '回数'; Kinds: [nhAdvertising, nhGifts]),
    (Code: 'c'; Caption: '広告回数'; Kinds: [nhAdvertising]),
    (Code: 'i'; Caption: '最新広告ID'; Kinds: [nhAdvertising]),
    (Code: 'f'; Caption: '貢献度'; Kinds: [nhAdvertising]),
    (Code: 'm'; Caption: '広告メッセージ'; Kinds: [nhAdvertising]),
    (Code: 'g'; Caption: 'ギフト名'; Kinds: [nhGifts]),
    (Code: 'c'; Caption: '貢献度'; Kinds: [nhGifts]),
    (Code: '%'; Caption: '％記号'; Kinds: [nhAdvertising, nhGifts]));
var
  Menu: TPopupMenu;
  Token: TFormatToken;
  Item: TMenuItem;
begin
  Menu := FFormat.PopupMenu;
  Menu.Items.Clear;
  for Token in Tokens do
    if FKind in Token.Kinds then
    begin
      Item := TMenuItem.Create(Menu);
      Item.Caption := '%' + Token.Code + '  ' + Token.Caption;
      Item.Tag := Ord(Token.Code);
      Item.OnClick := InsertFormatToken;
      Menu.Items.Add(Item);
    end;
  Item := TMenuItem.Create(Menu);
  Item.Caption := '-';
  Menu.Items.Add(Item);
  Item := TMenuItem.Create(Menu);
  Item.Caption := '初期書式に戻す';
  Item.OnClick := InsertFormatToken;
  Menu.Items.Add(Item);
end;

procedure TFormNicomeaSettings.InsertFormatToken(Sender: TObject);
var
  Code: NativeInt;
begin
  Code := TMenuItem(Sender).Tag;
  if Code = 0 then FFormat.Text := NICOMEA_DEFAULT_FORMAT[FKind]
  else FFormat.SelText := '%' + Char(Code);
  FFormat.SetFocus;
end;

procedure TFormNicomeaSettings.KindChanged(Sender: TObject);
var
  Index: Integer;
begin
  if FUpdating then Exit;
  Index := FKindSelector.ItemIndex;
  if (Index < Ord(Low(TNicomeaHistoryKind))) or (Index > Ord(High(TNicomeaHistoryKind))) or
    (Index = Ord(FKind)) then Exit;
  FKind := TNicomeaHistoryKind(Index);
  FLayout.Formats[FKind] := NICOMEA_DEFAULT_FORMAT[FKind];
  SyncFormatControls;
end;

procedure TFormNicomeaSettings.FormatChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  FLayout.Formats[FKind] := FFormat.Text;
  if FLayout.Formats[FKind] = '' then
    FLayout.Formats[FKind] := NICOMEA_DEFAULT_FORMAT[FKind];
  FDirty := True;
end;

procedure TFormNicomeaSettings.SyncControls;
var
  FontIndex: Integer;
begin
  FUpdating := True;
  try
    FStyle.ItemIndex := Ord(FLayout.Style);
    FEffect.ItemIndex := Ord(FLayout.Effect);
    FontIndex := FFont.Items.IndexOf(FLayout.FontName);
    if FontIndex < 0 then FontIndex := FFont.Items.Add(FLayout.FontName);
    FFont.ItemIndex := FontIndex;
    FSize.Position := FLayout.FontSize;
    FSpacing.Position := FLayout.LetterSpacing;
    FLineGap.Position := FLayout.LineGap;
    FSingleColumn.Checked := FLayout.SingleColumn;
    FSingleColumn.Enabled := FLayout.Style <> nsHorizontal;
    TNicomeaDarkButton(FBold).FAccent := FLayout.Bold;
    TNicomeaDarkButton(FItalic).FAccent := FLayout.Italic;
    TNicomeaDarkButton(FOutline).FAccent := FLayout.Outline;
    TNicomeaDarkButton(FShadow).FAccent := FLayout.Shadow;
    FBold.Invalidate;
    FItalic.Invalidate;
    FOutline.Invalidate;
    FShadow.Invalidate;
  finally
    FUpdating := False;
  end;
  FDirty := True;
  InvalidateDecorationSample;
end;

procedure TFormNicomeaSettings.ReadControls(Sender: TObject);
begin
  if FUpdating then Exit;
  if Sender = FFont then
  begin
    if FFont.ItemIndex >= 0 then FLayout.FontName := FFont.Items[FFont.ItemIndex];
  end
  else if Sender = FEffect then
  begin
    if FEffect.ItemIndex >= 0 then FLayout.Effect := TNicomeaEffect(FEffect.ItemIndex);
  end
  else if Sender = FSingleColumn then FLayout.SingleColumn := FSingleColumn.Checked
  else if Sender = FSize then FLayout.FontSize := FSize.Position
  else if Sender = FSpacing then FLayout.LetterSpacing := FSpacing.Position
  else if Sender = FLineGap then FLayout.LineGap := FLineGap.Position
  else if Sender = FSeparator then FLayout.Separator := FSeparator.Text;
  FDirty := True;
  if Sender = FFont then InvalidateDecorationSample;
end;

procedure TFormNicomeaSettings.StyleChanged(Sender: TObject);
var
  Index: Integer;
begin
  if FUpdating then Exit;
  Index := FStyle.ItemIndex;
  if (Index < 0) or (Index = Ord(FLayout.Style)) then Exit;
  FLayout.ResetStyle(TNicomeaStyle(Index), FFrameWidth, FFrameHeight);
  FPlayStart := GetTickCount64;
  FPausedProgress := 0.2;
  SyncControls;
end;

procedure TFormNicomeaSettings.ResetStyle(Sender: TObject);
begin
  FLayout.ResetStyle(FLayout.Style, FFrameWidth, FFrameHeight);
  SyncControls;
end;

procedure TFormNicomeaSettings.ToggleDecoration(Sender: TObject);
begin
  if Sender = FBold then FLayout.Bold := not FLayout.Bold
  else if Sender = FItalic then FLayout.Italic := not FLayout.Italic
  else if Sender = FOutline then FLayout.Outline := not FLayout.Outline
  else if Sender = FShadow then FLayout.Shadow := not FLayout.Shadow;
  SyncControls;
end;

function TFormNicomeaSettings.TargetColor: TColor;
begin
  case FColorTarget of
    ctOutline: Result := FLayout.OutlineColor;
    ctShadow: Result := FLayout.ShadowColor;
  else
    Result := FLayout.Color;
  end;
end;

procedure TFormNicomeaSettings.SyncColorPicker;
var
  Target: TColorTarget;
  Color: TColor;
begin
  Color := ColorToRGB(TargetColor);
  FHueBar.Color := HsvToColor(ColorHue(Color), 1, 1);
  FColorArea.BaseColor := FHueBar.Color;
  FColorArea.Color := Color;
  FColorSwatch.Color := Color;
  for Target := Low(TColorTarget) to High(TColorTarget) do
  begin
    TNicomeaDarkButton(FColorButtons[Target]).FAccent := Target = FColorTarget;
    FColorButtons[Target].Invalidate;
  end;
end;

procedure TFormNicomeaSettings.SelectColorTarget(Sender: TObject);
begin
  if TColorTarget(TButton(Sender).Tag) = FColorTarget then Exit;
  FColorTarget := TColorTarget(TButton(Sender).Tag);
  SyncColorPicker;
end;

procedure TFormNicomeaSettings.HueChanged(Sender: TObject);
var
  Saturation, Value: Double;
begin
  ColorToSv(FColorArea.Color, Saturation, Value);
  FColorArea.BaseColor := FHueBar.Color;
  FColorArea.Color := HsvToColor(ColorHue(FHueBar.Color), Saturation, Value);
  ColorChanged(Sender);
end;

procedure TFormNicomeaSettings.ColorChanged(Sender: TObject);
var
  Color: TColor;
  EnabledDecoration: Boolean;
begin
  Color := ColorToRGB(FColorArea.Color);
  if Color = ColorToRGB(TargetColor) then Exit;
  FColorSwatch.Color := Color;
  EnabledDecoration := False;
  case FColorTarget of
    ctText: FLayout.Color := Color;
    ctOutline:
      begin
        FLayout.OutlineColor := Color;
        EnabledDecoration := not FLayout.Outline;
        FLayout.Outline := True;
      end;
    ctShadow:
      begin
        FLayout.ShadowColor := Color;
        EnabledDecoration := not FLayout.Shadow;
        FLayout.Shadow := True;
      end;
  end;
  if EnabledDecoration then SyncControls
  else
  begin
    FDirty := True;
    InvalidateDecorationSample;
  end;
end;

function TFormNicomeaSettings.Progress: Double;
var
  Elapsed: Double;
begin
  if not FPlaying then Exit(FPausedProgress);
  Elapsed := (GetTickCount64 - FPlayStart) / 1000 / FDuration + FPausedProgress;
  Result := Frac(Elapsed);
end;

procedure TFormNicomeaSettings.UpdatePreviewCaption;
begin
  FHint.Caption := 'プレビュー  /  ' + FPreviewSource;
  if FPlaying then FHint.Caption := FHint.Caption + '  /  再生中'
  else FHint.Caption := FHint.Caption + '  /  一時停止中';
end;

procedure TFormNicomeaSettings.TogglePlayback;
begin
  FPausedProgress := Progress;
  FPlaying := not FPlaying;
  FPlayStart := GetTickCount64;
  UpdatePreviewCaption;
  FPreview.Invalidate;
end;

procedure TFormNicomeaSettings.DrawCombo(Control: TWinControl; Index: Integer; Bounds: TRect;
  State: TOwnerDrawState);
begin
  DrawSyncMusicStudioDarkComboBoxItem(TComboBox(Control), Index, Bounds, State, CurrentPPI);
end;

procedure TFormNicomeaSettings.RefreshBackground;
var
  Snapshot: TMusicStudioBackgroundSnapshot;
  X, Y: Integer;
  Row: PByte;
begin
  if not Assigned(FReadBackground) then Exit;
  if FReadBackground(FSerial, Snapshot) then
  begin
    if Snapshot.Serial = FSerial then Exit;
    FBackground.PixelFormat := pf32bit;
    FBackground.SetSize(Snapshot.Width, Snapshot.Height);
    for Y := 0 to Snapshot.Height - 1 do
    begin
      Row := FBackground.ScanLine[Y];
      for X := 0 to Snapshot.Width - 1 do
        with Snapshot.Pixels[Y * Snapshot.Width + X] do
        begin
          Row[0] := B;
          Row[1] := G;
          Row[2] := R;
          Row[3] := 0;
          Inc(Row, 4);
        end;
    end;
    FSerial := Snapshot.Serial;
    FPreview.Invalidate;
  end
  else if not FBackground.Empty then
  begin
    FSerial := 0;
    FBackground.SetSize(0, 0);
    FPreview.Invalidate;
  end;
end;

procedure TFormNicomeaSettings.PreviewTick(Sender: TObject);
begin
  RefreshBackground;
  if FDirty then
  begin
    FDirty := False;
    FRenderer.Prepare(FLayout, FSupporters, FKind);
    FPreview.Invalidate;
  end
  else if FPlaying then FPreview.Invalidate;
end;

function TFormNicomeaSettings.FitRect: TRect;
var
  Bounds: TRect;
  Margin: Integer;
begin
  Bounds := FPreview.ClientRect;
  Margin := MulDiv(24, CurrentPPI, 96);
  InflateRect(Bounds, -Margin, -Margin);
  Result := MusicStudioFitFrameRect(Bounds, FFrameWidth, FFrameHeight);
end;

function TFormNicomeaSettings.PreviewArea(const Frame: TRect): TRect;
var
  Area: TRect;
begin
  if Frame.IsEmpty or (FFrameWidth <= 0) or (FFrameHeight <= 0) then Exit(TRect.Empty);
  Area := NicomeaAreaRect(FLayout.Area, FFrameWidth, FFrameHeight, 0, 0, 1);
  Result := Rect(Frame.Left + MulDiv(Area.Left, Frame.Width, FFrameWidth),
    Frame.Top + MulDiv(Area.Top, Frame.Height, FFrameHeight),
    Frame.Left + MulDiv(Area.Right, Frame.Width, FFrameWidth),
    Frame.Top + MulDiv(Area.Bottom, Frame.Height, FFrameHeight));
end;

function TFormNicomeaSettings.DecorationHandle(Mode: TDecorationMode): TRect;
var
  X, Y, Size, Gap, Width: Integer;
begin
  Width := FDecorationSample.Width;
  Gap := Min(MulDiv(4, CurrentPPI, 96), Width div 12);
  Size := Min(MulDiv(22, CurrentPPI, 96), (Width - 4 * Gap) div 3);
  X := (Width - (3 * Size + 2 * Gap)) div 2 +
    (Ord(Mode) - Ord(Low(TDecorationMode))) * (Size + Gap);
  Y := FDecorationSample.Height - Size - Gap;
  Result := Rect(X, Y, X + Size, Y + Size);
end;

function TFormNicomeaSettings.DecorationEnabled(Mode: TDecorationMode): Boolean;
begin
  case Mode of
    dmOutline: Result := FLayout.Outline;
    dmShadow: Result := FLayout.Shadow;
  else
    Result := FLayout.Outline or FLayout.Shadow;
  end;
end;

function TFormNicomeaSettings.DecorationAt(const CursorPoint: TPoint): TDragMode;
var
  Mode: TDecorationMode;
begin
  for Mode := Low(TDecorationMode) to High(TDecorationMode) do
    if DecorationHandle(Mode).Contains(CursorPoint) then
      Exit(Mode);
  Result := dmNone;
end;

procedure TFormNicomeaSettings.InvalidateDecorationSample;
begin
  FDecorationDirty := True;
  FDecorationSample.Invalidate;
end;

procedure TFormNicomeaSettings.PaintDecorationSample(Sender: TObject);
const
  Captions: array[TDecorationMode] of string = ('縁', '影', 'ぼ');
  SampleWidth = 256;
  SampleHeight = 208;
var
  SampleLayout: TNicomeaLayout;
  Supporters: TArray<TNicomeaSupporter>;
  Target: TGPGraphics;
  Canvas: TCanvas;
  Mode: TDecorationMode;
  Sample, TextBounds, Bounds: TRect;
begin
  Sample := FDecorationSample.ClientRect;
  if Sample.IsEmpty then Exit;
  if FDecorationDirty then
  begin
    // 見本だけを固定サイズの1ページで描く。装飾は本番と共通のレンダラーを通す。
    SampleLayout := FLayout;
    SampleLayout.Style := nsPages;
    SampleLayout.Area := Rect(0, 0, SampleWidth, SampleHeight);
    SampleLayout.FontSize := 48;
    SampleLayout.LetterSpacing := 0;
    SampleLayout.LineGap := 0;
    SampleLayout.MaxChars := 0;
    SampleLayout.Formats[FKind] := '%n';
    SetLength(Supporters, 1);
    Supporters[0].Name := 'Aa';
    FDecorationRenderer.Prepare(SampleLayout, Supporters, FKind);
    FDecorationDirty := False;
  end;
  FDecorationBuffer.SetSize(Sample.Width, Sample.Height);
  Canvas := FDecorationBuffer.Canvas;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := $00787878;
  Canvas.Pen.Color := BUTTON_BORDER;
  Canvas.Rectangle(Sample);
  TextBounds := Sample;
  InflateRect(TextBounds, -MulDiv(3, CurrentPPI, 96), 0);
  Inc(TextBounds.Top, 1);
  TextBounds.Bottom := DecorationHandle(dmOutline).Top;
  TextBounds := MusicStudioFitFrameRect(TextBounds, SampleWidth, SampleHeight);
  Target := TGPGraphics.Create(Canvas.Handle);
  try
    FDecorationRenderer.DrawSample(Target, TextBounds);
  finally
    Target.Free;
  end;
  Canvas.Font.Assign(Font);
  for Mode := Low(TDecorationMode) to High(TDecorationMode) do
  begin
    Bounds := DecorationHandle(Mode);
    Canvas.Brush.Style := bsSolid;
    if FDragMode = Mode then
    begin
      Canvas.Brush.Color := ACCENT_BORDER;
      Canvas.Pen.Color := clWhite;
      Canvas.Font.Color := SYNC_MUSIC_STUDIO_DARK_BACKGROUND_COLOR;
    end
    else if DecorationEnabled(Mode) then
    begin
      Canvas.Brush.Color := BUTTON_ACCENT;
      Canvas.Pen.Color := ACCENT_BORDER;
      Canvas.Font.Color := clWhite;
    end
    else
    begin
      Canvas.Brush.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
      Canvas.Pen.Color := BUTTON_BORDER;
      Canvas.Font.Color := MUTED_TEXT;
    end;
    Canvas.Rectangle(Bounds);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Captions[Mode]), -1, Bounds,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  end;
  FDecorationSample.Canvas.Draw(0, 0, FDecorationBuffer);
end;

procedure TFormNicomeaSettings.PaintPreview(Sender: TObject);
var
  Frame, Area, VisibleFrame, Clipped: TRect;
  Canvas: TCanvas;
  Target: TGPGraphics;
  Gap, MarkLength: Integer;

  procedure Corner(X, Y, DX, DY: Integer);
  begin
    Canvas.MoveTo(X + DX * Gap, Y);
    Canvas.LineTo(X + DX * (Gap + MarkLength), Y);
    Canvas.MoveTo(X, Y + DY * Gap);
    Canvas.LineTo(X, Y + DY * (Gap + MarkLength));
  end;

begin
  if FPreview.ClientRect.IsEmpty then Exit;
  FBuffer.SetSize(FPreview.Width, FPreview.Height);
  Canvas := FBuffer.Canvas;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := $00404040;
  Canvas.FillRect(FPreview.ClientRect);
  Frame := FViewport.Frame(FitRect);
  if not Frame.IsEmpty then
  begin
    Canvas.Brush.Color := $00606060;
    Canvas.FillRect(Frame);
    if not FBackground.Empty then
      Canvas.StretchDraw(MusicStudioFitFrameRect(Frame, FBackground.Width, FBackground.Height), FBackground);
    Area := PreviewArea(Frame);
    if System.Types.IntersectRect(VisibleFrame, Frame, FPreview.ClientRect) and
      System.Types.IntersectRect(Clipped, Area, VisibleFrame) then
    begin
      Target := TGPGraphics.Create(Canvas.Handle);
      try
        FRenderer.DrawPreview(Target, Area, Clipped, Progress, FTimer.Interval / 1000 / FDuration);
      finally
        Target.Free;
      end;
    end;

    Gap := MulDiv(6, CurrentPPI, 96);
    MarkLength := MulDiv(12, CurrentPPI, 96);
    Canvas.Pen.Color := clWhite;
    Corner(Frame.Left, Frame.Top, -1, -1);
    Corner(Frame.Right - 1, Frame.Top, 1, -1);
    Corner(Frame.Left, Frame.Bottom - 1, -1, 1);
    Corner(Frame.Right - 1, Frame.Bottom - 1, 1, 1);
    if FSelected then DrawLipSyncPlacement(Canvas, Area, MulDiv(5, CurrentPPI, 96))
    else if not Area.IsEmpty then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Pen.Color := MUTED_TEXT;
      Canvas.Rectangle(Area);
    end;
  end;
  FPreview.Canvas.Draw(0, 0, FBuffer);
end;

procedure TFormNicomeaSettings.PreviewWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  CursorPoint: TPoint;
begin
  CursorPoint := FPreview.ScreenToClient(MousePos);
  if not FPreview.ClientRect.Contains(CursorPoint) then Exit;
  Handled := True;
  if (FDragControl <> nil) and (GetCaptureControl = FDragControl) then Exit;
  FViewport.ZoomAt(FitRect, CursorPoint, WheelDelta);
  FPreview.Invalidate;
end;

procedure TFormNicomeaSettings.EditMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Area: TRect;
  CursorPoint: TPoint;
begin
  if not (Button in [mbLeft, mbMiddle]) then Exit;
  if (FDragControl <> nil) and (Button <> FDragButton) and
    (GetCaptureControl = FDragControl) then Exit;
  CursorPoint := Point(X, Y);
  if Sender = FDecorationSample then
  begin
    if Button <> mbLeft then Exit;
    FDragMode := DecorationAt(CursorPoint);
    if FDragMode = dmNone then Exit;
  end
  else
  begin
    FDragMode := dmPan;
    if Button = mbLeft then
    begin
      Area := PreviewArea(FViewport.Frame(FitRect));
      FDragGrip := 0;
      if FSelected then FDragGrip := LipSyncGripAt(Area, CursorPoint, MulDiv(6, CurrentPPI, 96));
      FSelected := (FDragGrip <> 0) or Area.Contains(CursorPoint);
      if FSelected then
        if FDragGrip in [1..4] then FDragMode := dmResize
        else FDragMode := dmMove;
    end;
  end;
  FDragStart := CursorPoint;
  FDragLast := CursorPoint;
  FDragLayout := FLayout;
  FDragButton := Button;
  FDragMoved := False;
  FDragControl := TControl(Sender);
  SetCaptureControl(FDragControl);
  FDragControl.Invalidate;
end;

procedure TFormNicomeaSettings.EditMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
const
  DragHints: array[TDecorationMode] of string = (
    '左右にドラッグして縁取りの太さを調整',
    '上下左右にドラッグして影の位置を調整',
    '左右にドラッグして縁取りと影のぼかしを調整');
var
  Mode: TDragMode;
begin
  if (FDragMode <> dmNone) and (Sender = FDragControl) and
    (GetCaptureControl = FDragControl) then
    UpdateDrag(X, Y)
  else if Sender = FDecorationSample then
  begin
    Mode := DecorationAt(Point(X, Y));
    case Mode of
      dmOutline, dmBlur: FDecorationSample.Cursor := crSizeWE;
      dmShadow: FDecorationSample.Cursor := crSizeAll;
    else
      FDecorationSample.Cursor := crDefault;
    end;
    if Mode in [dmOutline, dmShadow, dmBlur] then
      FDecorationSample.Hint := DragHints[TDecorationMode(Mode)]
    else FDecorationSample.Hint := '';
  end;
end;

procedure TFormNicomeaSettings.UpdateDrag(X, Y: Integer);
var
  Frame, Area: TRect;
  DX, DY, NewStroke, NewShadowX, NewShadowY, NewBlur, Threshold: Integer;
  NewOutline, NewShadow, ToggleChanged: Boolean;
begin
  if not FDragMoved then
  begin
    // 左クリックと、表示位置・領域のドラッグをマウスの移動量で区別する。
    Threshold := Max(1, MulDiv(4, CurrentPPI, 96));
    if (FDragButton = mbLeft) and (FDragMode in [dmPan, dmMove, dmResize]) and
      (Abs(X - FDragStart.X) < Threshold) and (Abs(Y - FDragStart.Y) < Threshold) then Exit;
    FDragMoved := True;
  end;
  if FDragMode = dmPan then
  begin
    FViewport.PanBy(X - FDragLast.X, Y - FDragLast.Y);
    FDragLast := Point(X, Y);
    FPreview.Invalidate;
    Exit;
  end;
  if FDragMode in [dmOutline, dmShadow, dmBlur] then
  begin
    // 装飾の感度はプレビュー倍率やプロジェクト解像度と独立させる。
    DX := MulDiv(X - FDragStart.X, 96, CurrentPPI);
    DY := MulDiv(Y - FDragStart.Y, 96, CurrentPPI);
    NewStroke := FLayout.Stroke;
    NewShadowX := FLayout.ShadowX;
    NewShadowY := FLayout.ShadowY;
    NewBlur := FLayout.Blur;
    NewOutline := FLayout.Outline;
    NewShadow := FLayout.Shadow;
    case FDragMode of
      dmOutline:
        begin
          NewStroke := EnsureRange(FDragLayout.Stroke + DX div 2, 1, 32);
          if DX div 2 <> 0 then NewOutline := True;
        end;
      dmShadow:
        begin
          NewShadowX := EnsureRange(FDragLayout.ShadowX + DX, -64, 64);
          NewShadowY := EnsureRange(FDragLayout.ShadowY + DY, -64, 64);
          if (DX <> 0) or (DY <> 0) then NewShadow := True;
        end;
      dmBlur:
        begin
          NewBlur := EnsureRange(FDragLayout.Blur + DX div 2, 0, 24);
          if (DX div 2 <> 0) and (NewBlur > 0) and not NewShadow then NewOutline := True;
        end;
    end;
    ToggleChanged := (NewOutline <> FLayout.Outline) or (NewShadow <> FLayout.Shadow);
    if ToggleChanged or (NewStroke <> FLayout.Stroke) or (NewShadowX <> FLayout.ShadowX) or
      (NewShadowY <> FLayout.ShadowY) or (NewBlur <> FLayout.Blur) then
    begin
      FLayout.Outline := NewOutline;
      FLayout.Shadow := NewShadow;
      FLayout.Stroke := NewStroke;
      FLayout.ShadowX := NewShadowX;
      FLayout.ShadowY := NewShadowY;
      FLayout.Blur := NewBlur;
      if ToggleChanged then SyncControls
      else
      begin
        FDirty := True;
        InvalidateDecorationSample;
      end;
    end;
    Exit;
  end;
  Frame := FViewport.Frame(FitRect);
  if Frame.IsEmpty then Exit;
  DX := MulDiv(X - FDragStart.X, FFrameWidth, Frame.Width);
  DY := MulDiv(Y - FDragStart.Y, FFrameHeight, Frame.Height);
  Area := FDragLayout.Area;
  case FDragMode of
    dmMove:
      begin
        DX := EnsureRange(DX, -16384 - Area.Left, 16384 - Area.Left);
        DY := EnsureRange(DY, -16384 - Area.Top, 16384 - Area.Top);
        Area.Offset(DX, DY);
        FLayout.Area := Area;
        FPreview.Invalidate;
        Exit;
      end;
    dmResize:
      begin
        if FDragGrip in [1, 3] then
          Area.Left := EnsureRange(Area.Left + DX, Area.Right - 8192, Area.Right - 16)
        else Area.Right := EnsureRange(Area.Right + DX, Area.Left + 16, Area.Left + 8192);
        if FDragGrip in [1, 2] then
          Area.Top := EnsureRange(Area.Top + DY, Area.Bottom - 8192, Area.Bottom - 16)
        else Area.Bottom := EnsureRange(Area.Bottom + DY, Area.Top + 16, Area.Top + 8192);
        if FLayout.Area = Area then Exit;
        FLayout.Area := Area;
      end;
  end;
  FDirty := True;
end;

procedure TFormNicomeaSettings.EditMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (FDragMode = dmNone) or (Sender <> FDragControl) or (Button <> FDragButton) then Exit;
  // 左ボタンの OnMouseUp が呼ばれる時点で、VCL はキャプチャを解放済みの場合がある。
  UpdateDrag(X, Y);
  if GetCaptureControl = FDragControl then SetCaptureControl(nil);
  if (Button = mbLeft) and not FDragMoved and (FDragMode in [dmPan, dmMove]) then
    TogglePlayback;
  FDragMode := dmNone;
  FDragControl := nil;
  TControl(Sender).Invalidate;
end;

end.
