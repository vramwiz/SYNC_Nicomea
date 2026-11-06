library SYNC_Nicomea;

// ニコメアのAviUtl2 DLL境界。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  SYNC_MusicStudio_DarkTheme in 'Source\Lib\SYNC_MusicStudio_DarkTheme.pas',
  ColorPickerColorMath in 'Source\Lib\ColorPicker\ColorPickerColorMath.pas',
  ColorPickerHueBar in 'Source\Lib\ColorPicker\ColorPickerHueBar.pas',
  ColorPickerSVArea in 'Source\Lib\ColorPicker\ColorPickerSVArea.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  SYNC_MusicStudio_FramebufferCapture in 'Source\Common\Render\Host\SYNC_MusicStudio_FramebufferCapture.pas',
  SYNC_MusicStudio_HostBackground in 'Source\Common\Render\Host\SYNC_MusicStudio_HostBackground.pas',
  SYNC_MusicStudio_PsdTransform in 'Source\Common\Render\Placement\SYNC_MusicStudio_PsdTransform.pas',
  SYNC_LipSync_PreviewViewport in 'Source\Plugin\Filter\Preview\SYNC_LipSync_PreviewViewport.pas',
  SYNC_Nicomea_History in 'Source\Common\Nicovideo\SYNC_Nicomea_History.pas',
  SYNC_Nicomea_Layout in 'Source\Common\Nicovideo\SYNC_Nicomea_Layout.pas',
  SYNC_Nicomea_Renderer in 'Source\Common\Nicovideo\SYNC_Nicomea_Renderer.pas',
  SYNC_Nicomea_SettingsForm in 'Source\Plugin\Filter\SYNC_Nicomea_SettingsForm.pas',
  SYNC_Nicomea_FilterPlugin in 'Source\Plugin\Filter\SYNC_Nicomea_FilterPlugin.pas';

{$R *.res}

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if not StartNicomeaGraphics then Exit;
    SetNicomeaHostVersion(Version);
    GetNicomeaFilterTable;
    Result := 1;
  except
    StopNicomeaGraphics;
    // Delphi例外をAviUtl2のCコールバック境界へ漏らさない。
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  StopNicomeaGraphics;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetNicomeaFilterTable;
  except
    // 登録失敗時はテーブルを返さずホスト側へ判断を委ねる。
  end;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
