unit SYNC_Nicomea_Layout;

// 取得済み履歴の集計、書式展開と、表示領域・装飾の設定を管理する。
interface

uses
  System.JSON, System.Types, Vcl.Graphics, SYNC_Nicomea_History;

type
  TNicomeaStyle = (nsHorizontal, nsVertical, nsPages);
  TNicomeaEffect = (neNone, neFade);

  TNicomeaLayout = record
    Style: TNicomeaStyle;
    Effect: TNicomeaEffect;
    Area: TRect;
    FontName: string;
    FontSize: Integer;
    Color, OutlineColor, ShadowColor: TColor;
    Bold, Italic, Outline, Shadow, SingleColumn: Boolean;
    Stroke, ShadowX, ShadowY, Blur, LetterSpacing, LineGap, MaxChars: Integer;
    Honorific, Separator: string;
    Formats: array[TNicomeaHistoryKind] of string;
    procedure ResetStyle(NewStyle: TNicomeaStyle; Width, Height: Integer);
    class function Load(Settings: TJSONObject; Width, Height: Integer): TNicomeaLayout; static;
    procedure WriteTo(Settings: TJSONObject);
  end;

  TNicomeaSupporter = record
    Name, Gift, MessageText: string;
    Timestamp, Points, Contribution, HistoryID: Int64;
    Count: Integer;
  end;
  TNicomeaSupportersByKind = array[TNicomeaHistoryKind] of TArray<TNicomeaSupporter>;

const
  NICOMEA_VIDEO_KEY = 'videoId';
  NICOMEA_HISTORY_KEYS: array[TNicomeaHistoryKind] of string = ('advertisingHistory', 'giftHistory');
  NICOMEA_KIND_NAMES: array[TNicomeaHistoryKind] of string = ('広告', 'ギフト');
  NICOMEA_DEFAULT_FORMAT: array[TNicomeaHistoryKind] of string =
    ('%nさん（%c回・%ppt）', '%nさん（%g・%r回）');

function ReadNicomeaSettings(const JSON: string): TJSONObject;
function NicomeaSettingText(Obj: TJSONObject; const Key, Default: string): string;
function NicomeaStoredHistory(Obj: TJSONObject; Kind: TNicomeaHistoryKind): TNicomeaHistory;
function AggregateNicomeaHistory(const History: TNicomeaHistory): TArray<TNicomeaSupporter>;
function FormatNicomeaSupporter(const Supporter: TNicomeaSupporter;
  const FormatText, Honorific: string; Kind: TNicomeaHistoryKind): string;
function SampleNicomeaSupporters: TArray<TNicomeaSupporter>;

implementation

uses
  System.Classes, System.Generics.Collections, System.Math, System.SysUtils, System.UITypes;

function ReadNicomeaSettings(const JSON: string): TJSONObject;
var
  Data: TBytes;
begin
  Result := TJSONObject.Create;
  if JSON.Trim.IsEmpty then Exit;
  Data := TEncoding.UTF8.GetBytes(JSON);
  if Result.Parse(Data, 0, True) = Length(Data) then Exit;
  Result.Free;
  Result := TJSONObject.Create;
end;

function NicomeaSettingText(Obj: TJSONObject; const Key, Default: string): string;
var
  Value: TJSONValue;
begin
  Result := Default;
  Value := Obj.GetValue(Key);
  if Value is TJSONString then Result := Value.Value;
end;

function SettingInt(Obj: TJSONObject; const Key: string; Default, Min, Max: Integer): Integer;
var
  Value: TJSONValue;
begin
  Value := Obj.GetValue(Key);
  Result := Default;
  if Value is TJSONNumber then Result := StrToIntDef(Value.Value, Default);
  Result := EnsureRange(Result, Min, Max);
end;

function SettingBool(Obj: TJSONObject; const Key: string; Default: Boolean): Boolean;
var
  Value: TJSONValue;
begin
  Result := Default;
  Value := Obj.GetValue(Key);
  if Value is TJSONBool then Result := TJSONBool(Value).AsBoolean;
end;

procedure TNicomeaLayout.ResetStyle(NewStyle: TNicomeaStyle; Width, Height: Integer);
var
  W, H, Y: Integer;
begin
  Style := NewStyle;
  W := Max(32, Round(Width * 0.84));
  if Style = nsHorizontal then
  begin
    H := Max(24, Round(Height * 0.19));
    Y := Round(Height * 0.39) - H div 2;
  end
  else
  begin
    H := Max(24, Round(Height * 0.76));
    Y := -H div 2;
  end;
  Area := Rect(-W div 2, Y, -W div 2 + W, Y + H);
  LetterSpacing := 0;
  LineGap := Max(4, Round(Height * 0.011));
  SingleColumn := False;
end;

class function TNicomeaLayout.Load(Settings: TJSONObject; Width, Height: Integer): TNicomeaLayout;
var
  Value: TJSONValue;
  Obj: TJSONObject;
  X, Y, W, H: Integer;
begin
  Result := Default(TNicomeaLayout);
  Result.ResetStyle(nsHorizontal, Width, Height);
  Result.FontName := 'Yu Gothic UI';
  Result.FontSize := EnsureRange(Round(Height * 0.05), 12, 100);
  Result.Color := clWhite;
  Result.OutlineColor := clBlack;
  Result.ShadowColor := clBlack;
  Result.Outline := True;
  Result.Stroke := 2;
  Result.ShadowX := 4;
  Result.ShadowY := 4;
  // 保存済み書式に含まれる旧記号 %s の既定値。
  Result.Honorific := '様';
  Result.Separator := ' ';
  Result.Formats[nhAdvertising] := NICOMEA_DEFAULT_FORMAT[nhAdvertising];
  Result.Formats[nhGifts] := NICOMEA_DEFAULT_FORMAT[nhGifts];
  Value := Settings.GetValue('layout');
  if not (Value is TJSONObject) then Exit;
  Obj := TJSONObject(Value);
  Result.ResetStyle(TNicomeaStyle(SettingInt(Obj, 'style', Ord(Result.Style), 0, 2)), Width, Height);
  // 旧値3はフェード併用。旧値2の浮き上がり単独は既定値の「なし」で読む。
  case SettingInt(Obj, 'effect', Ord(neNone), 0, MaxInt) of
    Ord(neFade), 3: Result.Effect := neFade;
  end;
  X := SettingInt(Obj, 'left', Result.Area.Left, -16384, 16384);
  Y := SettingInt(Obj, 'top', Result.Area.Top, -16384, 16384);
  W := SettingInt(Obj, 'width', Result.Area.Width, 16, 8192);
  H := SettingInt(Obj, 'height', Result.Area.Height, 16, 8192);
  Result.Area := Rect(X, Y, X + W, Y + H);
  Result.FontName := NicomeaSettingText(Obj, 'font', Result.FontName);
  Result.FontSize := SettingInt(Obj, 'size', Result.FontSize, 6, 256);
  Result.Color := SettingInt(Obj, 'color', Result.Color, 0, $FFFFFF);
  Result.OutlineColor := SettingInt(Obj, 'outlineColor', Result.OutlineColor, 0, $FFFFFF);
  Result.ShadowColor := SettingInt(Obj, 'shadowColor', Result.ShadowColor, 0, $FFFFFF);
  Result.Bold := SettingBool(Obj, 'bold', Result.Bold);
  Result.Italic := SettingBool(Obj, 'italic', Result.Italic);
  Result.Outline := SettingBool(Obj, 'outline', Result.Outline);
  Result.Shadow := SettingBool(Obj, 'shadow', Result.Shadow);
  Result.SingleColumn := SettingBool(Obj, 'singleColumn', Result.SingleColumn);
  Result.Stroke := SettingInt(Obj, 'stroke', Result.Stroke, 1, 32);
  Result.ShadowX := SettingInt(Obj, 'shadowX', Result.ShadowX, -64, 64);
  Result.ShadowY := SettingInt(Obj, 'shadowY', Result.ShadowY, -64, 64);
  Result.Blur := SettingInt(Obj, 'blur', 0, 0, 24);
  Result.LetterSpacing := SettingInt(Obj, 'letterSpacing', 0, 0, 64);
  Result.LineGap := SettingInt(Obj, 'lineGap', Result.LineGap, 0, 128);
  Result.MaxChars := SettingInt(Obj, 'maxChars', 0, 0, 1000);
  Result.Honorific := NicomeaSettingText(Obj, 'honorific', Result.Honorific);
  Result.Separator := NicomeaSettingText(Obj, 'separator', Result.Separator);
  Result.Formats[nhAdvertising] := NicomeaSettingText(Obj, 'adFormat', Result.Formats[nhAdvertising]);
  Result.Formats[nhGifts] := NicomeaSettingText(Obj, 'giftFormat', Result.Formats[nhGifts]);
end;

procedure TNicomeaLayout.WriteTo(Settings: TJSONObject);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Settings.RemovePair('layout').Free;
  Settings.AddPair('layout', Obj);
  Obj.AddPair('style', Ord(Style));
  Obj.AddPair('effect', Ord(Effect));
  Obj.AddPair('left', Area.Left);
  Obj.AddPair('top', Area.Top);
  Obj.AddPair('width', Area.Width);
  Obj.AddPair('height', Area.Height);
  Obj.AddPair('font', FontName);
  Obj.AddPair('size', FontSize);
  Obj.AddPair('color', ColorToRGB(Color));
  Obj.AddPair('outlineColor', ColorToRGB(OutlineColor));
  Obj.AddPair('shadowColor', ColorToRGB(ShadowColor));
  Obj.AddPair('bold', Bold);
  Obj.AddPair('italic', Italic);
  Obj.AddPair('outline', Outline);
  Obj.AddPair('shadow', Shadow);
  Obj.AddPair('singleColumn', SingleColumn);
  Obj.AddPair('stroke', Stroke);
  Obj.AddPair('shadowX', ShadowX);
  Obj.AddPair('shadowY', ShadowY);
  Obj.AddPair('blur', Blur);
  Obj.AddPair('letterSpacing', LetterSpacing);
  Obj.AddPair('lineGap', LineGap);
  Obj.AddPair('maxChars', MaxChars);
  Obj.AddPair('honorific', Honorific);
  Obj.AddPair('separator', Separator);
end;

function NicomeaStoredHistory(Obj: TJSONObject; Kind: TNicomeaHistoryKind): TNicomeaHistory;
var
  Value: TJSONValue;
begin
  Value := Obj.GetValue(NICOMEA_HISTORY_KEYS[Kind]);
  Result := nil;
  if Value is TJSONArray then
    Result := NicomeaHistoryFromJSON(TJSONArray(Value), Kind);
end;

function AggregateNicomeaHistory(const History: TNicomeaHistory): TArray<TNicomeaSupporter>;
var
  Users: TDictionary<Int64, Integer>;
  Gifts: TDictionary<string, Byte>;
  Entry: TNicomeaHistoryEntry;
  Index, Count: Integer;
  GiftKey: string;
begin
  SetLength(Result, Length(History));
  Count := 0;
  Users := TDictionary<Int64, Integer>.Create;
  Gifts := TDictionary<string, Byte>.Create;
  try
    for Entry in History do
    begin
      if (Entry.UserID <= 0) or not Users.TryGetValue(Entry.UserID, Index) then
      begin
        Index := Count;
        Inc(Count);
        if Entry.UserID > 0 then Users.Add(Entry.UserID, Index);
      end;
      with Result[Index] do
      begin
        if (Count = 0) or (Entry.Timestamp > Timestamp) or (Name = '') then
        begin
          Name := Entry.Name;
          Timestamp := Entry.Timestamp;
          HistoryID := Entry.HistoryID;
        end;
        if MessageText = '' then MessageText := Entry.MessageText;
        if Entry.ItemName <> '' then
        begin
          GiftKey := IntToStr(Index) + ':' + Entry.ItemName;
          if not Gifts.ContainsKey(GiftKey) then
          begin
            Gifts.Add(GiftKey, 0);
            if Gift <> '' then Gift := Gift + '・';
            Gift := Gift + Entry.ItemName;
          end;
        end;
        Inc(Points, Entry.Points);
        Inc(Contribution, Entry.Contribution);
        Inc(Result[Index].Count);
      end;
    end;
  finally
    Gifts.Free;
    Users.Free;
  end;
  SetLength(Result, Count);
end;

function FormatNicomeaSupporter(const Supporter: TNicomeaSupporter;
  const FormatText, Honorific: string; Kind: TNicomeaHistoryKind): string;
var
  I: Integer;
  Name: string;
  Text: TStringBuilder;
begin
  Name := Supporter.Name;
  if Name = '' then Name := '匿名';
  Text := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(FormatText) do
    begin
      if (FormatText[I] = '%') and (I < Length(FormatText)) then
      begin
        Inc(I);
        case FormatText[I] of
          '%': Text.Append('%');
          'n': Text.Append(Name);
          's': Text.Append(Honorific);
          'r': Text.Append(Supporter.Count);
          'p': Text.Append(Supporter.Points);
          'c': if Kind = nhAdvertising then Text.Append(Supporter.Count)
               else Text.Append(Supporter.Contribution);
          'f': if Kind = nhAdvertising then Text.Append(Supporter.Contribution)
               else Text.Append('%f');
          'i': if Kind = nhAdvertising then Text.Append(Supporter.HistoryID)
               else Text.Append('%i');
          'm': if Kind = nhAdvertising then Text.Append(Supporter.MessageText)
               else Text.Append('%m');
          'g': if Kind = nhGifts then Text.Append(Supporter.Gift)
               else Text.Append('%g');
        else
          Text.Append('%').Append(FormatText[I]);
        end;
      end
      else
        Text.Append(FormatText[I]);
      Inc(I);
    end;
    Result := Text.ToString;
  finally
    Text.Free;
  end;
end;

function SampleNicomeaSupporters: TArray<TNicomeaSupporter>;
const
  Names: array[0..7] of string = ('ニコ太郎', 'みどり', 'こはる', 'しろねこ',
    '青いペン', 'はるか', '動画好き', '通りすがり');
var
  I: Integer;
begin
  SetLength(Result, Length(Names));
  for I := 0 to High(Result) do
  begin
    Result[I].Name := Names[I];
    Result[I].Gift := '花束';
    Result[I].Count := 1 + I mod 4;
    Result[I].Points := 5000 - I * 480;
    Result[I].Contribution := 20 + I;
    Result[I].HistoryID := 100 + I;
    Result[I].MessageText := '応援しています！';
  end;
end;

end.
