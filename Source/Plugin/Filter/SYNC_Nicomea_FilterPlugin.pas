unit SYNC_Nicomea_FilterPlugin;

// AviUtl2の標準パラメータ、設定の確定、フレームへの合成を接続する。
interface

uses
  AviUtl2FilterTypes;

function GetNicomeaFilterTable: PFILTER_PLUGIN_TABLE;
procedure SetNicomeaHostVersion(Version: Cardinal);

implementation

uses
  System.Classes, System.JSON, System.Math, System.SyncObjs, System.SysUtils, System.Types,
  System.UITypes, Winapi.GDIPAPI, Winapi.GDIPOBJ, Winapi.Messages, Winapi.Windows,
  Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.StdCtrls, PluginFilterTable,
  SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_HostBackground, SYNC_Nicomea_History,
  SYNC_Nicomea_Layout, SYNC_Nicomea_Renderer, SYNC_Nicomea_SettingsForm;

const
  EFFECT_NAME = 'ニコメア';
  JSON_ITEM_NAME = 'JSONデータ';
  VIDEO_ITEM_NAME = '動画ID';
  KIND_ITEM_NAME = '表示対象';
  FORMAT_ITEM_NAME = '書式';
  ALWAYS_HIDE_HOST_VERSION = 2011600;
  MAX_IMAGE_PIXELS = 33554432;

type
  TSettingsSession = class
  private
    FEdit: PEDIT_SECTION;
    FObject: OBJECT_HANDLE;
    FSceneID: Integer;
    function WriteItem(Name: PWideChar; const Value: string): Boolean;
  public
    Width, Height: Integer;
    Duration: Double;
    constructor Create(Edit: PEDIT_SECTION);
    function ReadBackground(AfterSerial: UInt64;
      out Snapshot: TMusicStudioBackgroundSnapshot): Boolean;
    function ReadItem(Name: PWideChar): string;
    procedure WriteItems(const Names, Values: array of string);
  end;

  TNicomeaFetchProgress = class(TForm)
  private
    FRequest: TNicomeaHistoryRequest;
    FLog: TMemo;
    FTimer: TTimer;
    FCloseButton: TButton;
    FClosing: Boolean;
    procedure Tick(Sender: TObject);
    procedure AllowClose(Sender: TObject; var CanClose: Boolean);
  public
    constructor CreateForRequest(Request: TNicomeaHistoryRequest);
  end;

  TNicomeaVideoSession = class
  private
    FBackground: TMusicStudioHostBackground;
    FRenderer: TNicomeaRenderer;
    FLock: TCriticalSection;
    FInput: TMusicStudioFramePixels;
    FJSON, FVideoID, FFormatText: string;
    FKind: TNicomeaHistoryKind;
    FDesignWidth, FDesignHeight: Integer;
    FLayout: TNicomeaLayout;
    procedure CaptureBackground(Video: PFILTER_PROC_VIDEO; Width, Height: Integer; var InputReady: Boolean);
    procedure Prepare(const JSON, VideoID, FormatText: string; Kind: TNicomeaHistoryKind;
      Width, Height: Integer);
    function Composite(Image: TGPBitmap; const Bounds: TRect; Width, Opacity: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Render(Video: PFILTER_PROC_VIDEO);
  end;

var
  SettingsButton, FetchButton: TFILTER_ITEM_BUTTON;
  VideoIDItem, FormatItem, JSONDataItem: TFILTER_ITEM_STRING;
  KindItem: TFILTER_ITEM_SELECT;
  KindHideRule: TFILTER_ITEM_HIDE_RULE;
  XItem, YItem, ScaleItem, TransparencyItem: TFILTER_ITEM_TRACK;
  StorageGroup: TFILTER_ITEM_GROUP;
  KindOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  PluginTableInitialized: Boolean;
  HostVersion: Cardinal;

procedure SetNicomeaHostVersion(Version: Cardinal);
begin
  HostVersion := Version;
end;

function DisplayKind(Value: Integer): TNicomeaHistoryKind;
begin
  if Value = Ord(nhGifts) then Result := nhGifts
  else Result := nhAdvertising;
end;

function DataVideoID(Settings: TJSONObject): string;
begin
  Result := NormalizeNicomeaVideoID(NicomeaSettingText(Settings, NICOMEA_VIDEO_KEY, ''));
end;

function ActiveVideoID(Settings: TJSONObject; const StandardID: string): string;
begin
  if StandardID.Trim = '' then Result := DataVideoID(Settings)
  else Result := NormalizeNicomeaVideoID(StandardID);
end;

function StoredSupporters(Settings: TJSONObject; const StandardID: string;
  Kind: TNicomeaHistoryKind): TArray<TNicomeaSupporter>;
begin
  Result := nil;
  if ActiveVideoID(Settings, StandardID) = DataVideoID(Settings) then
    Result := AggregateNicomeaHistory(NicomeaStoredHistory(Settings, Kind));
end;

constructor TSettingsSession.Create(Edit: PEDIT_SECTION);
var
  Info: PEDIT_INFO;
  Span: TOBJECT_LAYER_FRAME;
begin
  inherited Create;
  if (Edit = nil) or not Assigned(Edit^.GetFocusObject) or
    not Assigned(Edit^.GetObjectItemValue) or not Assigned(Edit^.SetObjectItemValue) then
    raise Exception.Create('AviUtl2の編集APIを取得できませんでした。');
  FEdit := Edit;
  FObject := FEdit^.GetFocusObject;
  if FObject = nil then raise Exception.Create('ニコメアを配置したオブジェクトを選択してください。');
  if Assigned(Edit^.CountObjectEffect) and (Edit^.CountObjectEffect(FObject, EFFECT_NAME) <> 1) then
    raise Exception.Create('設定対象にはニコメアを1つ配置してください。');
  Width := 1920;
  Height := 1080;
  Duration := 8;
  FSceneID := -1;
  Info := Edit^.Info;
  if Info = nil then Exit;
  if Info^.Width > 0 then Width := Info^.Width;
  if Info^.Height > 0 then Height := Info^.Height;
  FSceneID := Info^.SceneID;
  if (Info^.Rate > 0) and (Info^.Scale > 0) and Assigned(Edit^.GetObjectLayerFrame) then
  begin
    Span := Edit^.GetObjectLayerFrame(FObject);
    if (Span.StartFrame >= 0) and (Span.EndFrame >= Span.StartFrame) then
      Duration := (Int64(Span.EndFrame) - Span.StartFrame + 1) * Info^.Scale / Info^.Rate;
  end;
end;

function TSettingsSession.ReadBackground(AfterSerial: UInt64;
  out Snapshot: TMusicStudioBackgroundSnapshot): Boolean;
begin
  Result := ReadMusicStudioBackground(FObject, FSceneID, AfterSerial, Snapshot);
end;

function TSettingsSession.ReadItem(Name: PWideChar): string;
var
  Value: PAnsiChar;
begin
  Value := FEdit^.GetObjectItemValue(FObject, EFFECT_NAME, Name);
  if Value = nil then
    raise Exception.CreateFmt('「%s」を取得できませんでした。', [string(Name)]);
  Result := string(UTF8String(Value));
end;

function TSettingsSession.WriteItem(Name: PWideChar; const Value: string): Boolean;
var
  Encoded: UTF8String;
begin
  Encoded := UTF8String(Value);
  Result := FEdit^.SetObjectItemValue(FObject, EFFECT_NAME, Name, PAnsiChar(Encoded));
  if Result then Result := ReadItem(Name) = Value;
end;

procedure TSettingsSession.WriteItems(const Names, Values: array of string);
var
  Previous: TArray<string>;
  I, J: Integer;
  Restored: Boolean;
begin
  SetLength(Previous, Length(Names));
  for I := 0 to High(Names) do Previous[I] := ReadItem(PWideChar(Names[I]));
  for I := 0 to High(Names) do
    if Previous[I] <> Values[I] then
    try
      if not WriteItem(PWideChar(Names[I]), Values[I]) then
        raise Exception.CreateFmt('「%s」を完全に反映できませんでした。', [Names[I]]);
    except
      // 書き込み後に読み戻しが失敗した項目も含め、確定前の値へ戻す。
      Restored := True;
      for J := I downto 0 do
        if Previous[J] <> Values[J] then
          try
            if not WriteItem(PWideChar(Names[J]), Previous[J]) then
              if ReadItem(PWideChar(Names[J])) <> Previous[J] then Restored := False;
          except
            Restored := False;
          end;
      if not Restored then
        raise Exception.Create('設定の保存に失敗し、一部を元に戻せませんでした。');
      raise;
    end;
end;

constructor TNicomeaFetchProgress.CreateForRequest(Request: TNicomeaHistoryRequest);
var
  Footer: TPanel;
begin
  inherited CreateNew(nil);
  FRequest := Request;
  Caption := 'ニコメアのデータ取得';
  Position := poScreenCenter;
  ClientWidth := 470;
  ClientHeight := 265;
  Padding.SetBounds(12, 12, 12, 12);
  Font.Name := 'Yu Gothic UI';
  Font.Size := 10;
  ApplySyncMusicStudioDarkForm(Self);
  OnCloseQuery := AllowClose;
  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.BevelOuter := bvNone;
  Footer.Height := 39;
  Footer.Padding.Top := 8;
  ApplySyncMusicStudioDarkPanel(Footer);
  FCloseButton := TButton.Create(Self);
  FCloseButton.Parent := Footer;
  FCloseButton.Align := alRight;
  FCloseButton.Width := 90;
  FCloseButton.Cancel := True;
  FCloseButton.ModalResult := mrCancel;
  FCloseButton.Caption := '中止';
  ApplySyncMusicStudioDarkButton(FCloseButton);
  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.Align := alClient;
  FLog.ReadOnly := True;
  FLog.ScrollBars := ssVertical;
  ApplySyncMusicStudioDarkMemo(FLog);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
end;

procedure TNicomeaFetchProgress.AllowClose(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := WaitForSingleObject(FRequest.Handle, 0) = WAIT_OBJECT_0;
  if not CanClose and not FClosing then
  begin
    FClosing := True;
    FRequest.Terminate;
    FLog.Lines.Add('通信が終了したら閉じます。');
  end;
end;

procedure TNicomeaFetchProgress.Tick(Sender: TObject);
var
  Count: Integer;
  Done: Boolean;
begin
  Done := WaitForSingleObject(FRequest.Handle, 0) = WAIT_OBJECT_0;
  Count := FLog.Lines.Count;
  FRequest.DrainLog(FLog.Lines);
  if Count <> FLog.Lines.Count then
  begin
    FLog.SelStart := FLog.GetTextLen;
    FLog.Perform(EM_SCROLLCARET, 0, 0);
  end;
  if not Done then Exit;
  FTimer.Enabled := False;
  FCloseButton.Caption := '閉じる';
  if FClosing then ModalResult := mrCancel;
end;

procedure SettingsButtonCallback(Edit: PEDIT_SECTION); cdecl;
var
  Session: TSettingsSession;
  Form: TFormNicomeaSettings;
  Settings: TJSONObject;
  Layout: TNicomeaLayout;
  Kind, HistoryKind: TNicomeaHistoryKind;
  Supporters: TNicomeaSupportersByKind;
  FormatText, VideoID: string;
begin
  try
    Session := TSettingsSession.Create(Edit);
    try
      Settings := ReadNicomeaSettings(Session.ReadItem(JSON_ITEM_NAME));
      try
        Layout := TNicomeaLayout.Load(Settings, Session.Width, Session.Height);
        Kind := nhAdvertising;
        if Session.ReadItem(KIND_ITEM_NAME) = NICOMEA_KIND_NAMES[nhGifts] then Kind := nhGifts;
        FormatText := Session.ReadItem(FORMAT_ITEM_NAME);
        if FormatText <> '' then Layout.Formats[Kind] := FormatText;
        VideoID := Session.ReadItem(VIDEO_ITEM_NAME);
        for HistoryKind := Low(TNicomeaHistoryKind) to High(TNicomeaHistoryKind) do
          Supporters[HistoryKind] := StoredSupporters(Settings, VideoID, HistoryKind);
        Form := TFormNicomeaSettings.Create(nil);
        try
          Form.LoadLayout(Layout, Supporters,
            Kind, Session.Width, Session.Height, Session.Duration, Session.ReadBackground);
          if Form.ShowModal = mrOk then
          begin
            Layout := Form.Layout;
            Kind := Form.Kind;
            Layout.WriteTo(Settings);
            Session.WriteItems([KIND_ITEM_NAME, FORMAT_ITEM_NAME, JSON_ITEM_NAME],
              [NICOMEA_KIND_NAMES[Kind], Layout.Formats[Kind], Settings.ToJSON]);
          end;
        finally
          Form.Free;
        end;
      finally
        Settings.Free;
      end;
    finally
      Session.Free;
    end;
  except
    on E: Exception do
      try
        MessageDlg(E.Message, mtError, [mbOK], 0);
      except
        // Delphi例外をAviUtl2のコールバックへ漏らさない。
      end;
  end;
end;

procedure FetchButtonCallback(Edit: PEDIT_SECTION); cdecl;
var
  Session: TSettingsSession;
  Settings: TJSONObject;
  Request: TNicomeaHistoryRequest;
  Progress: TNicomeaFetchProgress;
  VideoID: string;
  Kind: TNicomeaHistoryKind;
begin
  try
    Session := TSettingsSession.Create(Edit);
    try
      Settings := ReadNicomeaSettings(Session.ReadItem(JSON_ITEM_NAME));
      try
        VideoID := ActiveVideoID(Settings, Session.ReadItem(VIDEO_ITEM_NAME));
        if VideoID = '' then raise Exception.Create('動画IDまたはニコニコ動画の視聴URLを入力してください。');
        Request := TNicomeaHistoryRequest.Create(VideoID);
        try
          Progress := TNicomeaFetchProgress.CreateForRequest(Request);
          try
            Request.Start;
            Progress.ShowModal;
          finally
            Progress.Free;
          end;
          Request.WaitFor;
          if not (Request.Succeeded(nhAdvertising) or Request.Succeeded(nhGifts)) then Exit;
          if VideoID <> DataVideoID(Settings) then
            for Kind := Low(Kind) to High(Kind) do
              Settings.RemovePair(NICOMEA_HISTORY_KEYS[Kind]).Free;
          Settings.RemovePair(NICOMEA_VIDEO_KEY).Free;
          Settings.AddPair(NICOMEA_VIDEO_KEY, VideoID);
          for Kind := Low(Kind) to High(Kind) do
            if Request.Succeeded(Kind) then
            begin
              Settings.RemovePair(NICOMEA_HISTORY_KEYS[Kind]).Free;
              Settings.AddPair(NICOMEA_HISTORY_KEYS[Kind],
                NicomeaHistoryToJSON(Request.History(Kind), Kind));
            end;
          Session.WriteItems([JSON_ITEM_NAME], [Settings.ToJSON]);
        finally
          Request.Free;
        end;
      finally
        Settings.Free;
      end;
    finally
      Session.Free;
    end;
  except
    on E: Exception do
      try
        MessageDlg(E.Message, mtError, [mbOK], 0);
      except
        // Delphi例外をAviUtl2のコールバックへ漏らさない。
      end;
  end;
end;

constructor TNicomeaVideoSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FBackground := TMusicStudioHostBackground.Create;
  FRenderer := TNicomeaRenderer.Create;
end;

destructor TNicomeaVideoSession.Destroy;
begin
  FRenderer.Free;
  FBackground.Free;
  FLock.Free;
  inherited;
end;

procedure TNicomeaVideoSession.CaptureBackground(Video: PFILTER_PROC_VIDEO; Width, Height: Integer;
  var InputReady: Boolean);
var
  Owner: OBJECT_HANDLE;
  Edit: PEDIT_SECTION;
  Layer, Frame, SceneID, CaptureWidth, CaptureHeight: Integer;
  Pixels: TMusicStudioFramePixels;
  Status: string;
begin
  Edit := Video^.Edit;
  if (Edit = nil) or not Assigned(Edit^.FindObject) or not Assigned(Edit^.CountObjectEffect) then
    Exit;
  Layer := Video^.Object_^.Layer;
  if Video^.Object_^.Flag and 1 <> 0 then
  begin
    if HostVersion < 2010300 then
      Exit;
    Layer := Video^.Object_^.EffectLayer;
  end;
  Frame := Video^.Object_^.FrameS + Video^.Object_^.Frame;
  Owner := Edit^.FindObject(Layer, Frame);
  if (Owner = nil) or (Edit^.CountObjectEffect(Owner, EFFECT_NAME) <> 1) then
    Exit;
  SceneID := -1;
  if Edit^.Info <> nil then SceneID := PEDIT_INFO(Edit^.Info)^.SceneID;
  // 専用画面の背景には対象の最初の取得フレームを使い、再生中の再取得を避ける。
  if FBackground.HasSnapshot(Owner, SceneID) then Exit;
  if FBackground.CaptureFramebuffer(Video^.GetFramebufferTexture2D,
    Pixels, CaptureWidth, CaptureHeight, Status) then
    FBackground.Publish(Owner, SceneID, Frame, CaptureWidth, CaptureHeight, Video^.Object_^.Time, Pixels)
  else if Assigned(Video^.GetImageData) and (Width > 0) and (Height > 0) then
  begin
    SetLength(FInput, NativeInt(Width) * Height);
    Video^.GetImageData(@FInput[0]);
    InputReady := True;
    // 背景のスナップショットと合成先は独立させる。
    FBackground.Publish(Owner, SceneID, Frame, Width, Height, Video^.Object_^.Time, Copy(FInput));
  end
  else FBackground.Clear(Status);
end;

procedure TNicomeaVideoSession.Prepare(const JSON, VideoID, FormatText: string;
  Kind: TNicomeaHistoryKind; Width, Height: Integer);
var
  Settings: TJSONObject;
begin
  if (FJSON = JSON) and (FVideoID = VideoID) and (FKind = Kind) and (FFormatText = FormatText) and
    (FDesignWidth = Width) and (FDesignHeight = Height) then Exit;
  Settings := ReadNicomeaSettings(JSON);
  try
    FLayout := TNicomeaLayout.Load(Settings, Width, Height);
    if FormatText <> '' then FLayout.Formats[Kind] := FormatText;
    FRenderer.Prepare(FLayout, StoredSupporters(Settings, VideoID, Kind), Kind);
  finally
    Settings.Free;
  end;
  FJSON := JSON;
  FVideoID := VideoID;
  FFormatText := FormatText;
  FKind := Kind;
  FDesignWidth := Width;
  FDesignHeight := Height;
end;

function TNicomeaVideoSession.Composite(Image: TGPBitmap; const Bounds: TRect;
  Width, Opacity: Integer): Boolean;
var
  Data: TBitmapData;
  Source: PByte;
  Target: PPIXEL_RGBA;
  X, Y, Alpha, Inverse: Integer;
begin
  Result := False;
  if Image.LockBits(MakeRect(0, 0, Bounds.Width, Bounds.Height), ImageLockModeRead,
    PixelFormat32bppPARGB, Data) <> Ok then Exit;
  try
    for Y := Bounds.Top to Bounds.Bottom - 1 do
    begin
      Source := PByte(NativeInt(Data.Scan0) + NativeInt(Y - Bounds.Top) * Data.Stride);
      Target := @FInput[Y * Width + Bounds.Left];
      for X := Bounds.Left to Bounds.Right - 1 do
      begin
        Alpha := (Source[3] * Opacity + 127) div 255;
        if Alpha > 0 then
        begin
          Result := True;
          Inverse := 255 - Alpha;
          Target^.R := Min(255, (Source[2] * Opacity + Target^.R * Inverse + 127) div 255);
          Target^.G := Min(255, (Source[1] * Opacity + Target^.G * Inverse + 127) div 255);
          Target^.B := Min(255, (Source[0] * Opacity + Target^.B * Inverse + 127) div 255);
          Target^.A := Min(255, Alpha + (Target^.A * Inverse + 127) div 255);
        end;
        Inc(Source, 4);
        Inc(Target);
      end;
    end;
  finally
    Image.UnlockBits(Data);
  end;
end;

procedure TNicomeaVideoSession.Render(Video: PFILTER_PROC_VIDEO);
var
  Width, Height, DesignWidth, DesignHeight, Opacity: Integer;
  X, Y, Scale, Progress: Double;
  Bounds, Clipped: TRect;
  InputReady: Boolean;
  Image: TGPBitmap;
  JSON, VideoID, FormatText: string;
  Kind: TNicomeaHistoryKind;
begin
  // 値ポインタは現在の描画コールバックでだけ有効。
  JSON := string(JSONDataItem.Value);
  VideoID := string(VideoIDItem.Value);
  FormatText := string(FormatItem.Value);
  Kind := DisplayKind(KindItem.Value);
  X := EnsureRange(XItem.Value, -32768.0, 32768.0);
  Y := EnsureRange(YItem.Value, -32768.0, 32768.0);
  Scale := EnsureRange(ScaleItem.Value, 0.0, 1000.0) / 100;
  Opacity := Round(255 * (100 - EnsureRange(TransparencyItem.Value, 0.0, 100.0)) / 100);
  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  if (Width < 0) or (Height < 0) or (Width > 8192) or (Height > 8192) or
    (Int64(Width) * Height > MAX_IMAGE_PIXELS) then Exit;

  InputReady := False;
  CaptureBackground(Video, Width, Height, InputReady);
  if (Opacity = 0) or (Scale <= 0) or (Width = 0) or (Height = 0) or
    not Assigned(Video^.GetImageData) or not Assigned(Video^.SetImageData) then Exit;
  DesignWidth := Width;
  DesignHeight := Height;
  if Video^.Scene <> nil then
  begin
    if Video^.Scene^.Width > 0 then DesignWidth := Video^.Scene^.Width;
    if Video^.Scene^.Height > 0 then DesignHeight := Video^.Scene^.Height;
  end;
  Prepare(JSON, VideoID, FormatText, Kind, DesignWidth, DesignHeight);
  if not FRenderer.HasContent then Exit;
  Bounds := NicomeaAreaRect(FLayout.Area, Width, Height, X, Y, Scale);
  if not System.Types.IntersectRect(Clipped, Bounds, Rect(0, 0, Width, Height)) then Exit;
  if Video^.Object_^.FrameTotal > 1 then
    Progress := Video^.Object_^.Frame / (Video^.Object_^.FrameTotal - 1)
  else Progress := 0.5;
  Image := FRenderer.RenderSurface(Bounds, Clipped, Progress);
  if Image = nil then Exit;
  if not InputReady then
  begin
    SetLength(FInput, NativeInt(Width) * Height);
    Video^.GetImageData(@FInput[0]);
  end;
  if Composite(Image, Clipped, Width, Opacity) then
    Video^.SetImageData(@FInput[0], Width, Height);
end;

function NicomeaProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Session: TNicomeaVideoSession;
begin
  Result := 1;
  try
    if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
    Session := TNicomeaVideoSession(Video^.UserData);
    Session.FLock.Acquire;
    try
      Session.Render(Video);
    finally
      Session.FLock.Release;
    end;
  except
    // 描画できないフレームではAviUtl2の入力を維持する。
  end;
end;

function NicomeaCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TNicomeaVideoSession.Create;
  except
  end;
end;

procedure NicomeaDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TNicomeaVideoSession(UserData).Free;
  except
  end;
end;

function GetNicomeaFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA,
      EFFECT_NAME, 'SYNC', 'ニコニコ動画の広告・ギフトへのお礼を表示', NicomeaProcVideo, nil);
    KindOptions[0].Name := PWideChar(NICOMEA_KIND_NAMES[nhAdvertising]);
    KindOptions[0].Value := Ord(nhAdvertising);
    KindOptions[1].Name := PWideChar(NICOMEA_KIND_NAMES[nhGifts]);
    KindOptions[1].Value := Ord(nhGifts);
    AddString(VideoIDItem, VIDEO_ITEM_NAME, '');
    AddButton(FetchButton, 'データ取得', FetchButtonCallback);
    AddButton(SettingsButton, '設定', SettingsButtonCallback);
    AddString(FormatItem, FORMAT_ITEM_NAME, '');
    AddTrack(XItem, 'X', 0, -4096, 4096, 0.1);
    AddTrack(YItem, 'Y', 0, -4096, 4096, 0.1);
    AddTrack(ScaleItem, '拡大率', 100, 0, 1000, 0.1);
    AddTrack(TransparencyItem, '透明度', 0, 0, 100, 0.1);
    AddGroup(StorageGroup, '内部データ', 0);
    AddSelect(KindItem, KIND_ITEM_NAME, Ord(nhAdvertising), @KindOptions[0]);
    AddString(JSONDataItem, JSON_ITEM_NAME, '{}');
    if HostVersion >= ALWAYS_HIDE_HOST_VERSION then AddAlwaysHideRule(KindHideRule, KIND_ITEM_NAME);
    GetPluginTable^.Func_Create := NicomeaCreate;
    GetPluginTable^.Func_Destroy := NicomeaDestroy;
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
