unit SYNC_Nicomea_SettingsForm;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.Graphics, Vcl.StdCtrls, SYNC_LipSync_PreviewViewport,
  SYNC_MusicStudio_HostBackground;

type
  TNicomeaSaveJSON = procedure(const JSON: string) of object;

  TFormNicomeaSettings = class(TForm)
  private
    FPreview: TPaintBox;
    FEditor: TMemo;
    FStatus: TLabel;
    FTimer: TTimer;
    FBackground: TBitmap;
    FBuffer: TBitmap;
    FReadBackground: TMusicStudioReadBackground;
    FSaveJSON: TNicomeaSaveJSON;
    FSerial: UInt64;
    FFrameWidth, FFrameHeight: Integer;
    FViewport: TLipSyncPreviewViewport;
    FDragPoint: TPoint;
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
    procedure LoadSettings(const JSON: string; Width, Height: Integer;
      ReadBackground: TMusicStudioReadBackground; SaveJSON: TNicomeaSaveJSON);
  end;

implementation

uses
  System.JSON, System.SysUtils, System.UITypes, Winapi.Windows, Vcl.Dialogs;

function ParseSettingsJSON(const Text: string): TJSONObject;
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(Text);
  Result := TJSONObject.Create;
  if Result.Parse(Bytes, 0, True) = Length(Bytes) then Exit;
  FreeAndNil(Result);
end;

constructor TFormNicomeaSettings.Create(AOwner: TComponent);
var
  Footer, EditorPanel: TPanel;
  Label_: TLabel;
  Button: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'ニコメアの設定';
  Position := poScreenCenter;
  ClientWidth := 1000;
  ClientHeight := 620;
  Constraints.MinWidth := 680;
  Constraints.MinHeight := 400;
  DoubleBuffered := True;
  OnMouseWheel := PreviewWheel;
  OnCloseQuery := SaveSettings;

  FBackground := Vcl.Graphics.TBitmap.Create;
  FBuffer := Vcl.Graphics.TBitmap.Create;

  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.BevelOuter := bvNone;
  Footer.Height := 44;
  Footer.Padding.SetBounds(8, 7, 8, 7);

  Button := TButton.Create(Self);
  Button.Parent := Footer;
  Button.Align := alRight;
  Button.Caption := 'キャンセル';
  Button.Cancel := True;
  Button.ModalResult := mrCancel;
  Button.Width := 100;

  Button := TButton.Create(Self);
  Button.Parent := Footer;
  Button.Align := alRight;
  Button.Caption := '保存';
  Button.Default := True;
  Button.ModalResult := mrOk;
  Button.Width := 84;
  Button.AlignWithMargins := True;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Footer;
  FStatus.Align := alClient;
  FStatus.Layout := tlCenter;
  FStatus.ShowAccelChar := False;
  FStatus.EllipsisPosition := epEndEllipsis;

  EditorPanel := TPanel.Create(Self);
  EditorPanel.Parent := Self;
  EditorPanel.Align := alRight;
  EditorPanel.BevelOuter := bvNone;
  EditorPanel.Width := 300;
  EditorPanel.Padding.SetBounds(8, 8, 8, 0);

  Label_ := TLabel.Create(Self);
  Label_.Parent := EditorPanel;
  Label_.Align := alTop;
  Label_.Caption := 'JSONデータ';

  FEditor := TMemo.Create(Self);
  FEditor.Parent := EditorPanel;
  FEditor.Align := alClient;
  FEditor.AlignWithMargins := True;
  FEditor.Margins.SetBounds(0, 6, 0, 0);
  FEditor.ScrollBars := ssBoth;
  FEditor.WordWrap := False;
  FEditor.WantReturns := True;
  FEditor.Font.Name := 'Consolas';

  FPreview := TPaintBox.Create(Self);
  FPreview.Parent := Self;
  FPreview.Align := alClient;
  FPreview.OnPaint := PaintPreview;
  FPreview.OnMouseDown := PreviewMouseDown;
  FPreview.OnMouseMove := PreviewMouseMove;
  FPreview.OnMouseUp := PreviewMouseUp;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 100;
  FTimer.OnTimer := RefreshBackground;
end;

destructor TFormNicomeaSettings.Destroy;
begin
  if Assigned(FTimer) then FTimer.Enabled := False;
  FBuffer.Free;
  FBackground.Free;
  inherited;
end;

procedure TFormNicomeaSettings.LoadSettings(const JSON: string; Width, Height: Integer;
  ReadBackground: TMusicStudioReadBackground; SaveJSON: TNicomeaSaveJSON);
var
  Value: TJSONObject;
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
  Value := ParseSettingsJSON(JSON);
  try
    if JSON.Trim.IsEmpty then
      FEditor.Text := '{}'
    else if Assigned(Value) then
      FEditor.Text := Value.Format(2)
    else
      FEditor.Text := JSON;
  finally
    Value.Free;
  end;
  RefreshBackground(nil);
  FTimer.Enabled := True;
end;

procedure TFormNicomeaSettings.SaveSettings(Sender: TObject; var CanClose: Boolean);
var
  Value: TJSONObject;
begin
  if ModalResult <> mrOk then Exit;
  CanClose := False;
  Value := ParseSettingsJSON(FEditor.Text);
  if Value = nil then
  begin
    MessageDlg('有効なJSONオブジェクトを入力してください。', mtWarning, [mbOK], 0);
    FEditor.SetFocus;
    Exit;
  end;
  try
    try
      FSaveJSON(Value.ToJSON);
      CanClose := True;
    except
      on E: Exception do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Value.Free;
  end;
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
end.

end.
