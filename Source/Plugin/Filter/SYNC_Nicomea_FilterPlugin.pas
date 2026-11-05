unit SYNC_Nicomea_FilterPlugin;

// AviUtl2の設定ボタンと、描画インスタンスごとの背景取得を接続する。
interface

uses
  AviUtl2FilterTypes;

function GetNicomeaFilterTable: PFILTER_PLUGIN_TABLE;
procedure SetNicomeaHostVersion(Version: Cardinal);

implementation

uses
  System.SysUtils, System.UITypes, Vcl.Dialogs, PluginFilterTable,
  SYNC_MusicStudio_HostBackground, SYNC_Nicomea_SettingsForm;

const
  EFFECT_NAME = 'ニコメア';
  JSON_ITEM_NAME = 'JSONデータ';

type
  TSettingsSession = class
    Edit: PEDIT_SECTION;
    Obj: OBJECT_HANDLE;
    SceneID: Integer;
    function ReadBackground(AfterSerial: UInt64;
      out Snapshot: TMusicStudioBackgroundSnapshot): Boolean;
    function ReadJSON: string;
    procedure SaveJSON(const JSON: string);
  end;

var
  SettingsButton: TFILTER_ITEM_BUTTON;
  JSONDataItem: TFILTER_ITEM_STRING;
  PluginTableInitialized: Boolean;
  HostVersion: Cardinal;

procedure SetNicomeaHostVersion(Version: Cardinal);
begin
  HostVersion := Version;
end;

function TSettingsSession.ReadBackground(AfterSerial: UInt64;
  out Snapshot: TMusicStudioBackgroundSnapshot): Boolean;
begin
  Result := ReadMusicStudioBackground(Obj, SceneID, AfterSerial, Snapshot);
end;

function TSettingsSession.ReadJSON: string;
var
  Value: PAnsiChar;
begin
  Value := Edit^.GetObjectItemValue(Obj, EFFECT_NAME, JSON_ITEM_NAME);
  if Value = nil then
    raise Exception.Create('JSONデータを取得できませんでした。');
  Result := string(UTF8String(Value));
end;

procedure TSettingsSession.SaveJSON(const JSON: string);
var
  Value: UTF8String;
begin
  if JSON = ReadJSON then Exit;
  Value := UTF8String(JSON);
  if not Edit^.SetObjectItemValue(Obj, EFFECT_NAME, JSON_ITEM_NAME,
    PAnsiChar(Value)) then
    raise Exception.Create('JSONデータを保存できませんでした。');
end;

procedure SettingsButtonCallback(Edit: PEDIT_SECTION); cdecl;
var
  Session: TSettingsSession;
  Form: TFormNicomeaSettings;
  Info: PEDIT_INFO;
  Width, Height: Integer;
begin
  try
    if (Edit = nil) or not Assigned(Edit^.GetFocusObject) or
      not Assigned(Edit^.GetObjectItemValue) or not Assigned(Edit^.SetObjectItemValue) then
      raise Exception.Create('AviUtl2の編集APIを取得できませんでした。');

    Session := TSettingsSession.Create;
    try
      Session.Edit := Edit;
      Session.Obj := Edit^.GetFocusObject;
      if Session.Obj = nil then
        raise Exception.Create('設定対象のオブジェクトを選択してください。');
      if Assigned(Edit^.CountObjectEffect) and
        (Edit^.CountObjectEffect(Session.Obj, EFFECT_NAME) <> 1) then
        raise Exception.Create('設定対象にはニコメアを1つ配置してください。');

      Width := 1920;
      Height := 1080;
      Session.SceneID := -1;
      Info := Edit^.Info;
      if Info <> nil then
      begin
        Width := Info^.Width;
        Height := Info^.Height;
        Session.SceneID := Info^.SceneID;
      end;

      Form := TFormNicomeaSettings.Create(nil);
      try
        Form.LoadSettings(Session.ReadJSON, Width, Height,
          Session.ReadBackground, Session.SaveJSON);
        Form.ShowModal;
      finally
        Form.Free;
      end;
    finally
      Session.Free;
    end;
  except
    on E: Exception do
      try
        MessageDlg('ニコメアの設定 - ' + E.Message, mtError, [mbOK], 0);
      except
        // Delphi例外をAviUtl2のコールバック境界へ漏らさない。
      end;
  end;
end;

procedure CaptureBackground(Video: PFILTER_PROC_VIDEO;
  Background: TMusicStudioHostBackground);
var
  Owner: OBJECT_HANDLE;
  Edit: PEDIT_SECTION;
  Layer, Frame, SceneID: Integer;
  Pixels: TMusicStudioFramePixels;
  Width, Height: Integer;
  Status: string;
begin
  Edit := Video^.Edit;
  if (Edit = nil) or not Assigned(Edit^.FindObject) or
    not Assigned(Edit^.CountObjectEffect) then
  begin
    Background.Clear;
    Exit;
  end;

  Layer := Video^.Object_^.Layer;
  if Video^.Object_^.Flag and 1 <> 0 then
  begin
    if HostVersion < 2010300 then
    begin
      Background.Clear;
      Exit;
    end;
    Layer := Video^.Object_^.EffectLayer;
  end;
  Frame := Video^.Object_^.FrameS + Video^.Object_^.Frame;
  Owner := Edit^.FindObject(Layer, Frame);
  if (Owner = nil) or (Edit^.CountObjectEffect(Owner, EFFECT_NAME) <> 1) then
  begin
    Background.Clear;
    Exit;
  end;
  SceneID := -1;
  if Edit^.Info <> nil then
    SceneID := PEDIT_INFO(Edit^.Info)^.SceneID;

  if Background.CaptureFramebuffer(Video^.GetFramebufferTexture2D,
    Pixels, Width, Height, Status) then
  begin
    Background.Publish(Owner, SceneID, Frame, Width, Height,
      Video^.Object_^.Time, Pixels, 'AviUtl2 合成画面');
    Exit;
  end;

  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  if Assigned(Video^.GetImageData) and (Width > 0) and (Height > 0) and
    (Width <= 8192) and (Height <= 8192) and (Int64(Width) * Height <= 33554432) then
  begin
    SetLength(Pixels, NativeInt(Width) * Height);
    Video^.GetImageData(@Pixels[0]);
    Background.Publish(Owner, SceneID, Frame, Width, Height,
      Video^.Object_^.Time, Pixels, 'AviUtl2 入力画像');
  end
  else
    Background.Clear(Status);
end;

function NicomeaProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 1;
  try
    if (Video <> nil) and (Video^.Object_ <> nil) and (Video^.UserData <> nil) then
      CaptureBackground(Video, TMusicStudioHostBackground(Video^.UserData));
  except
    // 背景取得に失敗した場合もAviUtl2の入力を維持する。
  end;
end;

function NicomeaCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TMusicStudioHostBackground.Create;
  except
  end;
end;

procedure NicomeaDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TMusicStudioHostBackground(UserData).Free;
  except
  end;
end;

function GetNicomeaFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA,
      EFFECT_NAME, 'SYNC', 'AviUtl2の背景プレビューとニコメアの設定',
      NicomeaProcVideo, nil);
    AddButton(SettingsButton, '設定', SettingsButtonCallback);
    AddString(JSONDataItem, JSON_ITEM_NAME, '{}');
    GetPluginTable^.Func_Create := NicomeaCreate;
    GetPluginTable^.Func_Destroy := NicomeaDestroy;
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
