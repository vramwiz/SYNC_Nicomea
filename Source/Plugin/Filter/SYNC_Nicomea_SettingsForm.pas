unit SYNC_Nicomea_SettingsForm;

// 動画IDの入力、履歴取得の進行表示、AviUtl2の背景プレビューを扱う。
interface

uses
  System.Classes, System.JSON, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Forms, Vcl.Graphics, Vcl.Grids, Vcl.StdCtrls, SYNC_LipSync_PreviewViewport,
  SYNC_MusicStudio_HostBackground, SYNC_Nicomea_History;

type
  TNicomeaSaveJSON = procedure(const JSON: string) of object;
  TNicomeaPage = TNicomeaHistoryKind;

  TFormNicomeaSettings = class(TForm)
  private
    FPreview: TPaintBox;
    FVideoID: TEdit;
    FFetchButton, FSaveButton: TButton;
    FLog: TMemo;
    FRequest: TNicomeaHistoryRequest;
    FCloseAfterFetch: Boolean;
    FHistoryGrids: array[TNicomeaPage] of TStringGrid;
    FHistoryStatus: array[TNicomeaPage] of TLabel;
    FPageButtons: array[TNicomeaPage] of TButton;
    FPages: array[TNicomeaPage] of TPanel;
    FStatus: TLabel;
    FTimer: TTimer;
    FBackground: TBitmap;
    FBuffer: TBitmap;
    FReadBackground: TMusicStudioReadBackground;
    FSaveJSON: TNicomeaSaveJSON;
    FSettings: TJSONObject;
    FOriginalVideoID: string;
    FSerial: UInt64;
    FFrameWidth, FFrameHeight: Integer;
    FViewport: TLipSyncPreviewViewport;
    FDragPoint: TPoint;
    procedure BuildPage(Page: TNicomeaPage; Parent: TWinControl;
      const Title: string; const Columns: array of string;
      const ColumnWidths: array of Integer);
    procedure FetchClick(Sender: TObject);
    procedure SetFetchBusy(Busy: Boolean);
    procedure TimerTick(Sender: TObject);
    procedure AppendLog(const Message: string);
    procedure UpdateHistory(Page: TNicomeaPage; const History: TNicomeaHistory);
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    procedure SelectPage(Page: TNicomeaPage);
    procedure PageClick(Sender: TObject);
    function FitRect: TRect;
    procedure RefreshBackground(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure PreviewWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure PreviewMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PreviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PreviewMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SaveSettings(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 選択中のオブジェクトの設定を読み込み、保存操作時にだけJSONを返す。
    procedure LoadSettings(const JSON: string; Width, Height: Integer;
      ReadBackground: TMusicStudioReadBackground; SaveJSON: TNicomeaSaveJSON);
  end;

implementation

uses
  System.DateUtils, System.SysUtils, System.UITypes, Winapi.Messages, Winapi.Windows,
  Vcl.Dialogs, SYNC_MusicStudio_DarkTheme;

const
  VIDEO_ID_KEY = 'videoId';
  MUTED_TEXT = TColor($00B5B5B5);
  DISABLED_TEXT = TColor($00888888);
  BUTTON_BORDER = TColor($00545454);
  BUTTON_ACCENT = TColor($006D492B);
  ACCENT_BORDER = TColor($00D6A778);

type
  // Windowsの配色設定にかかわらず、このフォームのボタンを暗色で描画する。
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
  FillColor, BorderColor, TextColor: TColor;
  Brush: HBRUSH;
  SavedDC: Integer;
begin
  Item := Message.DrawItemStruct;
  Bounds := Item^.rcItem;
  if FAccent and Enabled then
  begin
    FillColor := BUTTON_ACCENT;
    BorderColor := ACCENT_BORDER;
  end
  else
  begin
    FillColor := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
    BorderColor := BUTTON_BORDER;
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
    TextColor := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
    if not Enabled then TextColor := DISABLED_TEXT;
    SetTextColor(Item^.hDC, ColorToRGB(TextColor));
    DrawText(Item^.hDC, PChar(Caption), -1, Bounds,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
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

function NewDarkPanel(Parent: TWinControl; Alignment: TAlign): TPanel;
begin
  Result := TPanel.Create(Parent);
  Result.Parent := Parent;
  Result.BevelOuter := bvNone;
  Result.Top := Parent.ClientHeight;
  Result.Align := Alignment;
  Result.StyleElements := [];
  ApplySyncMusicStudioDarkPanel(Result);
end;

function ParseSettingsJSON(const Text: string): TJSONObject;
var
  Bytes: TBytes;
begin
  Result := TJSONObject.Create;
  if Text.Trim.IsEmpty then Exit;
  Bytes := TEncoding.UTF8.GetBytes(Text);
  if Result.Parse(Bytes, 0, True) = Length(Bytes) then Exit;
  FreeAndNil(Result);
end;

constructor TFormNicomeaSettings.Create(AOwner: TComponent);
const
  PAGE_CAPTIONS: array[TNicomeaPage] of string = ('広告', 'ギフト');
var
  Footer, SettingsPanel, VideoPanel, VideoRow, InputPanel, PageBar, LogPanel, PreviewPanel: TPanel;
  Label_: TLabel;
  Button: TNicomeaDarkButton;
  Page: TNicomeaPage;
begin
  inherited CreateNew(AOwner);
  Caption := 'ニコメアの設定';
  Position := poScreenCenter;
  ClientWidth := 1100;
  ClientHeight := 620;
  Constraints.MinWidth := 820;
  Constraints.MinHeight := 490;
  Padding.SetBounds(12, 12, 12, 12);
  Font.Name := 'Yu Gothic UI';
  Font.Size := 10;
  StyleElements := [];
  DoubleBuffered := True;
  OnMouseWheel := PreviewWheel;
  OnCloseQuery := SaveSettings;
  ApplySyncMusicStudioDarkForm(Self);

  FBackground := Vcl.Graphics.TBitmap.Create;
  FBuffer := Vcl.Graphics.TBitmap.Create;

  Footer := NewDarkPanel(Self, alBottom);
  Footer.Color := SYNC_MUSIC_STUDIO_DARK_BACKGROUND_COLOR;
  Footer.Height := 36;
  Footer.AlignWithMargins := True;
  Footer.Margins.SetBounds(0, 12, 0, 0);

  Button := TNicomeaDarkButton.Create(Self);
  Button.Parent := Footer;
  Button.Align := alRight;
  Button.Caption := 'キャンセル';
  Button.Cancel := True;
  Button.ModalResult := mrCancel;
  Button.Width := 102;

  Button := TNicomeaDarkButton.Create(Self);
  Button.Parent := Footer;
  Button.Align := alRight;
  Button.Caption := '保存';
  Button.Default := True;
  Button.ModalResult := mrOk;
  Button.Width := 84;
  Button.AlignWithMargins := True;
  Button.Margins.SetBounds(0, 0, 8, 0);
  Button.FAccent := True;
  FSaveButton := Button;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Footer;
  FStatus.Align := alClient;
  FStatus.Layout := tlCenter;
  FStatus.Font.Color := MUTED_TEXT;
  FStatus.ShowAccelChar := False;
  FStatus.EllipsisPosition := epEndEllipsis;

  SettingsPanel := NewDarkPanel(Self, alRight);
  SettingsPanel.Width := 462;
  SettingsPanel.AlignWithMargins := True;
  SettingsPanel.Margins.SetBounds(12, 0, 0, 0);
  SettingsPanel.Padding.SetBounds(16, 16, 16, 16);

  VideoPanel := NewDarkPanel(SettingsPanel, alTop);
  VideoPanel.Height := 62;

  Label_ := TLabel.Create(Self);
  Label_.Parent := VideoPanel;
  Label_.Caption := '動画 ID';
  Label_.Font.Style := [fsBold];

  VideoRow := NewDarkPanel(VideoPanel, alBottom);
  VideoRow.Height := 34;

  Button := TNicomeaDarkButton.Create(Self);
  Button.Parent := VideoRow;
  Button.Align := alLeft;
  Button.AlignWithMargins := True;
  Button.Margins.SetBounds(0, 0, 8, 0);
  Button.Width := 76;
  Button.Caption := '取得';
  Button.FAccent := True;
  Button.OnClick := FetchClick;
  FFetchButton := Button;

  InputPanel := NewDarkPanel(VideoRow, alClient);
  InputPanel.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  InputPanel.Padding.SetBounds(8, 6, 8, 4);
  FVideoID := TEdit.Create(Self);
  FVideoID.Parent := InputPanel;
  FVideoID.Align := alClient;
  FVideoID.AutoSize := False;
  FVideoID.TextHint := '動画 ID または視聴 URL';
  FVideoID.BorderStyle := bsNone;
  FVideoID.StyleElements := [];
  ApplySyncMusicStudioDarkEdit(FVideoID);
  Label_.FocusControl := FVideoID;

  PageBar := NewDarkPanel(SettingsPanel, alTop);
  PageBar.Height := 36;
  PageBar.AlignWithMargins := True;
  PageBar.Margins.SetBounds(0, 14, 0, 12);
  for Page := Low(TNicomeaPage) to High(TNicomeaPage) do
  begin
    Button := TNicomeaDarkButton.Create(Self);
    Button.Parent := PageBar;
    Button.Align := alLeft;
    Button.AlignWithMargins := True;
    Button.Margins.SetBounds(0, 0, 8, 0);
    Button.Width := 94;
    Button.Caption := PAGE_CAPTIONS[Page];
    Button.Tag := Ord(Page);
    Button.OnClick := PageClick;
    FPageButtons[Page] := Button;
  end;

  LogPanel := NewDarkPanel(SettingsPanel, alBottom);
  LogPanel.Height := 128;
  LogPanel.AlignWithMargins := True;
  LogPanel.Margins.SetBounds(0, 12, 0, 0);
  Label_ := TLabel.Create(Self);
  Label_.Parent := LogPanel;
  Label_.Align := alTop;
  Label_.AlignWithMargins := True;
  Label_.Margins.SetBounds(0, 0, 0, 6);
  Label_.Caption := '取得ログ';
  Label_.Font.Style := [fsBold];

  FLog := TMemo.Create(Self);
  FLog.Parent := LogPanel;
  FLog.Align := alClient;
  FLog.BorderStyle := bsNone;
  FLog.ReadOnly := True;
  FLog.ScrollBars := ssVertical;
  FLog.WantReturns := False;
  ApplySyncMusicStudioDarkMemo(FLog);

  BuildPage(nhAdvertising, SettingsPanel, '広告履歴',
    ['開始日', '広告者', 'ポイント'], [108, 195, 86]);
  BuildPage(nhGifts, SettingsPanel, 'ギフト履歴',
    ['日時', '支援者', 'ギフト名', 'ポイント', '貢献度'], [132, 70, 76, 60, 56]);
  SelectPage(nhAdvertising);

  PreviewPanel := NewDarkPanel(Self, alClient);
  PreviewPanel.Padding.SetBounds(10, 8, 10, 10);
  Label_ := TLabel.Create(Self);
  Label_.Parent := PreviewPanel;
  Label_.Align := alTop;
  Label_.AlignWithMargins := True;
  Label_.Margins.SetBounds(0, 0, 0, 8);
  Label_.Caption := 'プレビュー';
  Label_.Font.Style := [fsBold];

  FPreview := TPaintBox.Create(Self);
  FPreview.Parent := PreviewPanel;
  FPreview.Align := alClient;
  FPreview.OnPaint := PaintPreview;
  FPreview.OnMouseDown := PreviewMouseDown;
  FPreview.OnMouseMove := PreviewMouseMove;
  FPreview.OnMouseUp := PreviewMouseUp;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 100;
  FTimer.OnTimer := TimerTick;
  ActiveControl := FVideoID;
end;

procedure TFormNicomeaSettings.BuildPage(Page: TNicomeaPage; Parent: TWinControl;
  const Title: string; const Columns: array of string;
  const ColumnWidths: array of Integer);
var
  Panel: TPanel;
  Label_: TLabel;
  Grid: TStringGrid;
  I: Integer;
begin
  Panel := NewDarkPanel(Parent, alClient);
  FPages[Page] := Panel;

  Label_ := TLabel.Create(Self);
  Label_.Parent := Panel;
  Label_.Align := alTop;
  Label_.AlignWithMargins := True;
  Label_.Margins.SetBounds(0, 0, 0, 8);
  Label_.Caption := Title;
  Label_.Font.Style := [fsBold];

  Label_ := TLabel.Create(Self);
  Label_.Parent := Panel;
  Label_.Align := alBottom;
  Label_.AlignWithMargins := True;
  Label_.Margins.SetBounds(0, 8, 0, 0);
  Label_.Caption := '取得待ち';
  FHistoryStatus[Page] := Label_;
  Label_.Font.Color := MUTED_TEXT;

  Grid := TStringGrid.Create(Self);
  FHistoryGrids[Page] := Grid;
  Grid.Parent := Panel;
  Grid.Align := alClient;
  Grid.BorderStyle := bsNone;
  Grid.Ctl3D := False;
  Grid.StyleElements := [];
  Grid.DrawingStyle := gdsClassic;
  Grid.Color := SYNC_MUSIC_STUDIO_DARK_BACKGROUND_COLOR;
  Grid.FixedColor := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  Grid.ColCount := Length(Columns);
  Grid.FixedCols := 0;
  Grid.RowCount := 2;
  Grid.FixedRows := 1;
  Grid.DefaultRowHeight := 28;
  Grid.Options := [goFixedVertLine, goFixedHorzLine, goRowSelect];
  Grid.RowHeights[1] := 0;
  Grid.ScrollBars := ssVertical;
  Grid.TabStop := False;
  for I := 0 to High(Columns) do
  begin
    Grid.Cells[I, 0] := Columns[I];
    Grid.ColWidths[I] := ColumnWidths[I];
  end;
end;

procedure TFormNicomeaSettings.SelectPage(Page: TNicomeaPage);
var
  Item: TNicomeaPage;
  Button: TNicomeaDarkButton;
begin
  for Item := Low(TNicomeaPage) to High(TNicomeaPage) do
  begin
    FPages[Item].Visible := Item = Page;
    Button := TNicomeaDarkButton(FPageButtons[Item]);
    Button.FAccent := Item = Page;
    Button.Invalidate;
  end;
end;

procedure TFormNicomeaSettings.PageClick(Sender: TObject);
begin
  SelectPage(TNicomeaPage(TButton(Sender).Tag));
end;

destructor TFormNicomeaSettings.Destroy;
begin
  if Assigned(FTimer) then FTimer.Enabled := False;
  FRequest.Free;
  FSettings.Free;
  FBuffer.Free;
  FBackground.Free;
  inherited;
end;

procedure TFormNicomeaSettings.LoadSettings(const JSON: string; Width, Height: Integer;
  ReadBackground: TMusicStudioReadBackground; SaveJSON: TNicomeaSaveJSON);
var
  Value: TJSONValue;
begin
  FFrameWidth := Width;
  FFrameHeight := Height;
  if (Width <= 0) or (Height <= 0) then
  begin
    FFrameWidth := 1920;
    FFrameHeight := 1080;
  end;
  FReadBackground := ReadBackground;
  FSaveJSON := SaveJSON;
  FreeAndNil(FSettings);
  FSettings := ParseSettingsJSON(JSON);
  FOriginalVideoID := '';
  if Assigned(FSettings) then
  begin
    Value := FSettings.GetValue(VIDEO_ID_KEY);
    if Value is TJSONString then
      FOriginalVideoID := Value.Value;
  end;
  FVideoID.Text := FOriginalVideoID;
  AppendLog('動画 ID または視聴 URL を入力して取得してください。');
  RefreshBackground(nil);
  FTimer.Enabled := True;
end;

procedure TFormNicomeaSettings.SaveSettings(Sender: TObject; var CanClose: Boolean);
var
  VideoID: string;
begin
  if Assigned(FRequest) then
  begin
    CanClose := False;
    if (ModalResult <> mrOk) and not FCloseAfterFetch then
    begin
      FCloseAfterFetch := True;
      FRequest.Terminate;
      AppendLog('中止を要求しました。通信終了後に閉じます。');
    end;
    Exit;
  end;
  if ModalResult <> mrOk then Exit;
  VideoID := Trim(FVideoID.Text);
  if VideoID = FOriginalVideoID then Exit;
  CanClose := False;
  if VideoID <> '' then
  begin
    VideoID := NormalizeNicomeaVideoID(VideoID);
    if VideoID = '' then
    begin
      MessageDlg('ニコニコ動画の動画 ID または視聴 URL を入力してください。',
        mtWarning, [mbOK], 0);
      ActiveControl := FVideoID;
      Exit;
    end;
  end;
  if FSettings = nil then
  begin
    MessageDlg('AviUtl2側の「JSONデータ」を有効なJSONオブジェクトに直してから保存してください。',
      mtWarning, [mbOK], 0);
    Exit;
  end;
  FSettings.RemovePair(VIDEO_ID_KEY).Free;
  if VideoID <> '' then
    FSettings.AddPair(VIDEO_ID_KEY, VideoID);
  try
    FSaveJSON(FSettings.ToJSON);
    CanClose := True;
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFormNicomeaSettings.CMDialogKey(var Message: TCMDialogKey);
begin
  if (Message.CharCode = VK_RETURN) and Assigned(FVideoID) and (ActiveControl = FVideoID) then
  begin
    FetchClick(FVideoID);
    Message.Result := 1;
  end
  else
    inherited;
end;

procedure TFormNicomeaSettings.AppendLog(const Message: string);
begin
  FLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Message);
  FLog.SelStart := FLog.GetTextLen;
  FLog.Perform(EM_SCROLLCARET, 0, 0);
end;

procedure TFormNicomeaSettings.SetFetchBusy(Busy: Boolean);
begin
  FFetchButton.Enabled := not Busy;
  FSaveButton.Enabled := not Busy;
  FVideoID.ReadOnly := Busy;
  if Busy then
    FFetchButton.Caption := '取得中'
  else
    FFetchButton.Caption := '取得';
end;

procedure TFormNicomeaSettings.FetchClick(Sender: TObject);
var
  VideoID: string;
  Page: TNicomeaPage;
begin
  if Assigned(FRequest) then Exit;
  FLog.Clear;
  VideoID := NormalizeNicomeaVideoID(FVideoID.Text);
  if VideoID = '' then
  begin
    AppendLog('取得失敗 - ニコニコ動画の動画 ID または視聴 URL を入力してください。');
    ActiveControl := FVideoID;
    Exit;
  end;

  FVideoID.Text := VideoID;
  for Page := Low(TNicomeaPage) to High(TNicomeaPage) do
  begin
    UpdateHistory(Page, nil);
    FHistoryStatus[Page].Caption := '取得中…';
  end;
  SetFetchBusy(True);
  try
    FRequest := TNicomeaHistoryRequest.Create(VideoID);
    FRequest.Start;
  except
    on E: Exception do
    begin
      FreeAndNil(FRequest);
      SetFetchBusy(False);
      for Page := Low(TNicomeaPage) to High(TNicomeaPage) do
        FHistoryStatus[Page].Caption := '取得失敗';
      AppendLog('取得完了 - 失敗（' + E.Message + '）');
    end;
  end;
end;

procedure TFormNicomeaSettings.TimerTick(Sender: TObject);
var
  Page: TNicomeaPage;
  PreviousLogCount: Integer;
  Done: Boolean;
begin
  if Assigned(FRequest) then
  begin
    Done := WaitForSingleObject(FRequest.Handle, 0) = WAIT_OBJECT_0;
    PreviousLogCount := FLog.Lines.Count;
    FRequest.DrainLog(FLog.Lines);
    if FLog.Lines.Count <> PreviousLogCount then
    begin
      FLog.SelStart := FLog.GetTextLen;
      FLog.Perform(EM_SCROLLCARET, 0, 0);
    end;

    if Done then
    begin
      try
        if not FCloseAfterFetch then
          for Page := Low(TNicomeaPage) to High(TNicomeaPage) do
            UpdateHistory(Page, FRequest.History(Page));
      finally
        FreeAndNil(FRequest);
        SetFetchBusy(False);
      end;
      if FCloseAfterFetch then
      begin
        FCloseAfterFetch := False;
        ModalResult := mrCancel;
        Exit;
      end;
    end;
  end;
  RefreshBackground(Sender);
end;

procedure TFormNicomeaSettings.UpdateHistory(Page: TNicomeaPage;
  const History: TNicomeaHistory);
var
  Grid: TStringGrid;
  I: Integer;
  DateFormat: string;
begin
  Grid := FHistoryGrids[Page];
  Grid.RowCount := 2;
  Grid.Rows[1].Clear;
  if Length(History) = 0 then
    Grid.RowHeights[1] := 0
  else
  begin
    Grid.RowCount := Length(History) + 1;
    Grid.RowHeights[1] := Grid.DefaultRowHeight;
    if Page = nhAdvertising then
      DateFormat := 'yyyy/mm/dd'
    else
      DateFormat := 'yyyy/mm/dd hh:nn';
    for I := 0 to High(History) do
    begin
      if (History[I].Timestamp > 0) and (History[I].Timestamp <= 253402300799) then
        Grid.Cells[0, I + 1] := FormatDateTime(DateFormat, UnixToDateTime(History[I].Timestamp));
      Grid.Cells[1, I + 1] := History[I].Name;
      if Page = nhAdvertising then
        Grid.Cells[2, I + 1] := IntToStr(History[I].Points)
      else
      begin
        Grid.Cells[2, I + 1] := History[I].ItemName;
        Grid.Cells[3, I + 1] := IntToStr(History[I].Points);
        Grid.Cells[4, I + 1] := IntToStr(History[I].Contribution);
      end;
    end;
  end;
  FHistoryStatus[Page].Caption := Format('表示 %d 件', [Length(History)]);
end;

procedure TFormNicomeaSettings.RefreshBackground(Sender: TObject);
var
  Snapshot: TMusicStudioBackgroundSnapshot;
  X, Y: Integer;
  Row: PByte;
  Status: string;
begin
  if FReadBackground(FSerial, Snapshot) then
  begin
    if Snapshot.Serial <> FSerial then
    begin
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
    end;
  end
  else if not FBackground.Empty then
  begin
    FSerial := 0;
    FBackground.SetSize(0, 0);
    FPreview.Invalidate;
  end;
  Status := StringReplace(Snapshot.Status, sLineBreak, ' / ', [rfReplaceAll]);
  if FStatus.Caption <> Status then FStatus.Caption := Status;
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

procedure TFormNicomeaSettings.PaintPreview(Sender: TObject);
var
  Frame: TRect;
  Canvas: TCanvas;
  Gap, MarkLength: Integer;

  procedure DrawCorner(X, Y, DX, DY: Integer);
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
  Canvas.Brush.Color := $00404040;
  Canvas.FillRect(FPreview.ClientRect);
  Frame := FViewport.Frame(FitRect);
  if not Frame.IsEmpty then
  begin
    Canvas.Brush.Color := $00606060;
    Canvas.FillRect(Frame);
    if not FBackground.Empty then
      Canvas.StretchDraw(MusicStudioFitFrameRect(Frame, FBackground.Width,
        FBackground.Height), FBackground);

    Gap := MulDiv(6, CurrentPPI, 96);
    MarkLength := MulDiv(12, CurrentPPI, 96);
    Canvas.Pen.Color := clWhite;
    DrawCorner(Frame.Left, Frame.Top, -1, -1);
    DrawCorner(Frame.Right - 1, Frame.Top, 1, -1);
    DrawCorner(Frame.Left, Frame.Bottom - 1, -1, 1);
    DrawCorner(Frame.Right - 1, Frame.Bottom - 1, 1, 1);
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
  FViewport.ZoomAt(FitRect, CursorPoint, WheelDelta);
  FPreview.Invalidate;
  Handled := True;
end;

procedure TFormNicomeaSettings.PreviewMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then Exit;
  FDragPoint := Point(X, Y);
  SetCaptureControl(FPreview);
end;

procedure TFormNicomeaSettings.PreviewMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
begin
  if not (ssLeft in Shift) or (GetCaptureControl <> FPreview) then Exit;
  FViewport.PanBy(X - FDragPoint.X, Y - FDragPoint.Y);
  FDragPoint := Point(X, Y);
  FPreview.Invalidate;
end;

procedure TFormNicomeaSettings.PreviewMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (GetCaptureControl = FPreview) then
  begin
    PreviewMouseMove(Sender, Shift + [ssLeft], X, Y);
    SetCaptureControl(nil);
  end;
end;

end.
