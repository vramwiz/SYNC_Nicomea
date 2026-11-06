unit SYNC_Nicomea_Renderer;

// 実際の文字幅から配置を決め、プレビューと映像で同じグリフと時間計算を使う。
interface

uses
  System.Generics.Collections, System.Types, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  SYNC_Nicomea_Layout, SYNC_Nicomea_History;

type
  TNicomeaRenderer = class
  private type
    TCell = record
      Text: string;
      X, Y, Width, Height, Page: Integer;
      IsSeparator: Boolean;
    end;
  private
    FSettings: TNicomeaLayout;
    FFont: TGPFontFamily;
    FFontStyle: Integer;
    FFormat: TGPStringFormat;
    FCells: TArray<TCell>;
    FCache: TObjectDictionary<Integer, TGPBitmap>;
    FCacheOrder: TQueue<Integer>;
    FCacheBytes: Int64;
    FGlyphMargin, FRowHeight, FSpan, FPageCount: Integer;
    FSurface: TGPBitmap;
    function BuildPath(const Text: string): TGPGraphicsPath;
    function FitText(const Text: string; MaxChars: Integer; out W, H: Integer): string;
    function BuildGlyph(const Cell: TCell): TGPBitmap;
    function Glyph(Index: Integer): TGPBitmap;
    function FirstVisible(Threshold, Page: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    // 再配置する。フレーム描画からは呼ばず、データや設定が変わったときだけ呼ぶ。
    procedure Prepare(const Settings: TNicomeaLayout;
      const Supporters: TArray<TNicomeaSupporter>; Kind: TNicomeaHistoryKind);
    // Destinationは表示領域の画面座標。Progressはオブジェクト内の0～1。
    procedure Draw(Target: TGPGraphics; const Destination: TRect; Progress: Double);
    // クリップ済み範囲へ描画する。返した画像は次の描画までレンダラーが所有する。
    function RenderSurface(const Destination, Clipped: TRect; Progress: Double): TGPBitmap;
    function HasContent: Boolean;
  end;

function NicomeaAreaRect(const Area: TRect; Width, Height: Integer;
  X, Y, Scale: Double): TRect;
function StartNicomeaGraphics: Boolean;
procedure StopNicomeaGraphics;

implementation

uses
  System.Math, System.SysUtils, System.UITypes, System.Character, Winapi.Windows, Vcl.Graphics;

const
  CACHE_BUDGET = 32 * 1024 * 1024;
  MAX_TEXT_UNITS = 4096;
  CELL_PADDING = 4;
  SEPARATOR_CACHE_INDEX = -1;

var
  GraphicsToken: ULONG_PTR;

function StartNicomeaGraphics: Boolean;
var
  Input: TGdiplusStartupInput;
begin
  if GraphicsToken <> 0 then Exit(True);
  Input := Default(TGdiplusStartupInput);
  Input.GdiplusVersion := 1;
  Result := GdiplusStartup(GraphicsToken, @Input, nil) = Ok;
end;

procedure StopNicomeaGraphics;
begin
  if GraphicsToken = 0 then Exit;
  GdiplusShutdown(GraphicsToken);
  GraphicsToken := 0;
end;

function NicomeaAreaRect(const Area: TRect; Width, Height: Integer;
  X, Y, Scale: Double): TRect;
begin
  X := X + Width / 2;
  Y := Y + Height / 2;
  Result := Rect(Round(X + Area.Left * Scale), Round(Y + Area.Top * Scale),
    Round(X + Area.Right * Scale), Round(Y + Area.Bottom * Scale));
end;

function SafePrefix(const Text: string; Units: Integer): string;
begin
  if Units >= Length(Text) then Exit(Text);
  if (Units > 0) and Text[Units].IsHighSurrogate then Dec(Units);
  Result := Copy(Text, 1, Units);
end;

procedure BlurDecoration(Image: TGPBitmap; Width, Height, Radius: Integer; HasColor: Boolean);
var
  Data: TBitmapData;
  Temp: TBytes;
  X, Y, I, Sum, Diameter, Channel, FirstChannel: Integer;
  Row: PByte;
begin
  if Radius <= 0 then Exit;
  if Image.LockBits(MakeRect(0, 0, Width, Height), ImageLockModeRead or ImageLockModeWrite,
    PixelFormat32bppPARGB, Data) <> Ok then Exit;
  try
    Diameter := Radius * 2 + 1;
    SetLength(Temp, Width * Height);
    // 黒い装飾はアルファだけ、有色の装飾は乗算済みのRGBも同じ範囲でぼかす。
    FirstChannel := 3;
    if HasColor then FirstChannel := 0;
    for Channel := FirstChannel to 3 do
    begin
      for Y := 0 to Height - 1 do
      begin
        Row := PByte(NativeInt(Data.Scan0) + NativeInt(Y) * Data.Stride + Channel);
        Sum := 0;
        for I := 0 to Min(Radius - 1, Width - 1) do Inc(Sum, Row[I * 4]);
        for X := 0 to Width - 1 do
        begin
          if X + Radius < Width then Inc(Sum, Row[(X + Radius) * 4]);
          Temp[Y * Width + X] := (Sum + Radius) div Diameter;
          if X >= Radius then Dec(Sum, Row[(X - Radius) * 4]);
        end;
      end;
      for X := 0 to Width - 1 do
      begin
        Sum := 0;
        for I := 0 to Min(Radius - 1, Height - 1) do Inc(Sum, Temp[I * Width + X]);
        for Y := 0 to Height - 1 do
        begin
          if Y + Radius < Height then Inc(Sum, Temp[(Y + Radius) * Width + X]);
          Row := PByte(NativeInt(Data.Scan0) + NativeInt(Y) * Data.Stride + Channel);
          Row[X * 4] := (Sum + Radius) div Diameter;
          if Y >= Radius then Dec(Sum, Temp[(Y - Radius) * Width + X]);
        end;
      end;
    end;
  finally
    Image.UnlockBits(Data);
  end;
end;

constructor TNicomeaRenderer.Create;
begin
  inherited;
  FCache := TObjectDictionary<Integer, TGPBitmap>.Create([doOwnsValues]);
  FCacheOrder := TQueue<Integer>.Create;
  FFormat := TGPStringFormat.Create(0);
end;

destructor TNicomeaRenderer.Destroy;
begin
  FSurface.Free;
  FCache.Free;
  FCacheOrder.Free;
  FFormat.Free;
  FFont.Free;
  inherited;
end;

function TNicomeaRenderer.BuildPath(const Text: string): TGPGraphicsPath;
var
  CharacterPath: TGPGraphicsPath;
  Part: string;
  Bounds: TGPRectF;
  I, Units: Integer;
  X: Single;
begin
  Result := TGPGraphicsPath.Create;
  if FSettings.LetterSpacing = 0 then
  begin
    Result.AddString(Text, Length(Text), FFont, FFontStyle, FSettings.FontSize,
      MakePoint(0.0, 0.0), FFormat);
    Exit;
  end;
  CharacterPath := TGPGraphicsPath.Create;
  try
    X := 0;
    I := 1;
    while I <= Length(Text) do
    begin
      Units := 1;
      if Text[I].IsHighSurrogate and (I < Length(Text)) and Text[I + 1].IsLowSurrogate then
        Units := 2;
      Part := Copy(Text, I, Units);
      CharacterPath.Reset;
      CharacterPath.AddString(Part, Length(Part), FFont, FFontStyle,
        FSettings.FontSize, MakePoint(X, 0.0), FFormat);
      Bounds := Default(TGPRectF);
      CharacterPath.GetBounds(Bounds);
      Result.AddPath(CharacterPath, False);
      X := X + Max(FSettings.FontSize * 0.22, Bounds.Width) + FSettings.LetterSpacing;
      Inc(I, Units);
    end;
  finally
    CharacterPath.Free;
  end;
end;

function TNicomeaRenderer.FitText(const Text: string; MaxChars: Integer; out W, H: Integer): string;
var
  FullText, Candidate: string;
  Lo, Hi, Mid, Width, Height: Integer;

  procedure Measure(const Value: string; out AWidth, AHeight: Integer);
  var
    Bounds: TGPRectF;
    Path: TGPGraphicsPath;
  begin
    Bounds := Default(TGPRectF);
    Path := BuildPath(Value);
    try
      Path.GetBounds(Bounds);
    finally
      Path.Free;
    end;
    AWidth := Ceil(Bounds.Width) + 2 * CELL_PADDING;
    AHeight := Ceil(Bounds.Height) + 2 * CELL_PADDING;
  end;

begin
  FullText := StringReplace(StringReplace(Text, #13, ' ', [rfReplaceAll]),
    #10, ' ', [rfReplaceAll]);
  if (MaxChars > 0) and (Length(FullText) > MaxChars) then
    FullText := SafePrefix(FullText, MaxChars - 1) + '…';
  FullText := SafePrefix(FullText, MAX_TEXT_UNITS);
  Result := FullText;
  Measure(Result, W, H);
  if W <= FSettings.Area.Width then Exit;

  Result := '…';
  Measure(Result, W, H);
  Lo := 1;
  Hi := Length(FullText) - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    Candidate := SafePrefix(FullText, Mid) + '…';
    Measure(Candidate, Width, Height);
    if Width <= FSettings.Area.Width then
    begin
      Result := Candidate;
      W := Width;
      H := Height;
      Lo := Mid + 1;
    end
    else
      Hi := Mid - 1;
  end;
end;

procedure TNicomeaRenderer.Prepare(const Settings: TNicomeaLayout;
  const Supporters: TArray<TNicomeaSupporter>; Kind: TNicomeaHistoryKind);
var
  Supporter: TNicomeaSupporter;
  Text, SeparatorText, TrimmedLeft: string;
  Cells: TArray<TCell>;
  SeparatorCell: TCell;
  I, Count, Placed, X, Y, Gap, LeadingGap, TrailingGap, SpaceWidth: Integer;
  RowStart, Row, RowsPerPage, RowPitch, Page, DecorationExtent: Integer;

  procedure CenterRow(Last: Integer);
  var
    J, Indent: Integer;
  begin
    Indent := Max(0, (Settings.Area.Width - X) div 2);
    for J := RowStart to Last do Inc(FCells[J].X, Indent);
  end;

  procedure PlaceCell(const Cell: TCell);
  begin
    FCells[Placed] := Cell;
    FCells[Placed].X := X;
    FCells[Placed].Y := Y;
    FCells[Placed].Page := Page;
    Inc(X, Cell.Width);
    Inc(Placed);
  end;

begin
  FSettings := Settings;
  FCache.Clear;
  FCacheOrder.Clear;
  FCacheBytes := 0;
  FCells := nil;
  FSpan := 0;
  FPageCount := 0;
  if Length(Supporters) = 0 then Exit;
  FreeAndNil(FFont);
  FFont := TGPFontFamily.Create(PWideChar(Settings.FontName));
  if FFont.GetLastStatus <> Ok then
  begin
    FFont.Free;
    FFont := TGPFontFamily.Create('Yu Gothic UI');
    if FFont.GetLastStatus <> Ok then
    begin
      FFont.Free;
      FFont := TGPFontFamily.Create('Segoe UI');
    end;
  end;
  FFontStyle := FontStyleRegular;
  if Settings.Bold then FFontStyle := FFontStyle or FontStyleBold;
  if Settings.Italic then FFontStyle := FFontStyle or FontStyleItalic;
  // 装飾用の余白は文字の行送りやスクロール距離に含めない。
  DecorationExtent := 0;
  if Settings.Outline then DecorationExtent := Settings.Stroke;
  if Settings.Shadow then
    DecorationExtent := Max(DecorationExtent, Max(Abs(Settings.ShadowX), Abs(Settings.ShadowY)));
  if Settings.Outline or Settings.Shadow then Inc(DecorationExtent, Settings.Blur);
  FGlyphMargin := Max(0, 2 + DecorationExtent - CELL_PADDING);

  SetLength(Cells, Length(Supporters));
  Count := 0;
  FRowHeight := Settings.FontSize;
  for Supporter in Supporters do
  begin
    Text := FormatNicomeaSupporter(Supporter, Settings.Formats[Kind], Settings.Honorific, Kind);
    if Text.Trim.IsEmpty then Continue;
    Cells[Count].Text := FitText(Text, Settings.MaxChars, Cells[Count].Width, Cells[Count].Height);
    FRowHeight := Max(FRowHeight, Cells[Count].Height);
    Inc(Count);
  end;
  if Count = 0 then Exit;

  SeparatorCell := Default(TCell);
  LeadingGap := 0;
  TrailingGap := 0;
  if (Count > 1) and ((Settings.Style = nsHorizontal) or not Settings.SingleColumn) then
  begin
    SeparatorText := SafePrefix(Settings.Separator, MAX_TEXT_UNITS);
    TrimmedLeft := SeparatorText.TrimLeft;
    Text := TrimmedLeft.TrimRight;
    // 半角スペース1つは従来の項目間隔に合わせる。
    SpaceWidth := Max(4, Settings.FontSize div 2);
    LeadingGap := (Length(SeparatorText) - Length(TrimmedLeft)) * SpaceWidth;
    TrailingGap := (Length(TrimmedLeft) - Length(Text)) * SpaceWidth;
    if Text <> '' then
    begin
      SeparatorCell.Text := FitText(Text, 0, SeparatorCell.Width, SeparatorCell.Height);
      SeparatorCell.IsSeparator := True;
      FRowHeight := Max(FRowHeight, SeparatorCell.Height);
    end;
  end;
  Gap := LeadingGap + SeparatorCell.Width + TrailingGap;
  if SeparatorCell.IsSeparator then SetLength(FCells, Count * 2 - 1)
  else SetLength(FCells, Count);
  Placed := 0;
  RowPitch := FRowHeight + Settings.LineGap;
  RowsPerPage := Max(1, (Settings.Area.Height + Settings.LineGap) div RowPitch);
  X := 0;
  Y := 0;
  Row := 0;
  RowStart := 0;
  Page := 0;
  for I := 0 to Count - 1 do
  begin
    if (Settings.Style <> nsHorizontal) and (X > 0) and
      (Settings.SingleColumn or (X + Gap + Cells[I].Width > Settings.Area.Width)) then
    begin
      CenterRow(Placed - 1);
      X := 0;
      RowStart := Placed;
      Inc(Row);
      Inc(Y, RowPitch);
      if (Settings.Style = nsPages) and (Row mod RowsPerPage = 0) then
      begin
        Inc(Page);
        Y := 0;
      end;
    end;
    if X > 0 then
    begin
      Inc(X, LeadingGap);
      if SeparatorCell.IsSeparator then PlaceCell(SeparatorCell);
      Inc(X, TrailingGap);
    end;
    PlaceCell(Cells[I]);
  end;
  SetLength(FCells, Placed);
  if Settings.Style = nsHorizontal then
    FSpan := X
  else
  begin
    CenterRow(Placed - 1);
    FSpan := Y + FRowHeight;
  end;
  FPageCount := Page + 1;
end;

function TNicomeaRenderer.BuildGlyph(const Cell: TCell): TGPBitmap;
var
  Path: TGPGraphicsPath;
  Bounds: TGPRectF;
  Graphics: TGPGraphics;
  Brush: TGPSolidBrush;
  Pen: TGPPen;
  Padding, Width, Height: Integer;

  function GlyphColor(Value: TColor; Alpha: Byte): ARGB;
  var
    RGBColor: COLORREF;
  begin
    RGBColor := ColorToRGB(Value);
    Result := MakeColor(Alpha, GetRValue(RGBColor), GetGValue(RGBColor), GetBValue(RGBColor));
  end;

begin
  Padding := CELL_PADDING + FGlyphMargin;
  Width := Cell.Width + 2 * FGlyphMargin;
  Height := Cell.Height + 2 * FGlyphMargin;
  Result := TGPBitmap.Create(Width, Height, PixelFormat32bppPARGB);
  Path := BuildPath(Cell.Text);
  try
    Bounds := Default(TGPRectF);
    Path.GetBounds(Bounds);
    Graphics := TGPGraphics.Create(Result);
    try
      Graphics.Clear(0);
      Graphics.SetSmoothingMode(SmoothingModeAntiAlias);
      if FSettings.Shadow then
      begin
        Graphics.TranslateTransform(Padding - Bounds.X + FSettings.ShadowX,
          Padding - Bounds.Y + FSettings.ShadowY);
        Brush := TGPSolidBrush.Create(GlyphColor(FSettings.ShadowColor, 175));
        try
          Graphics.FillPath(Brush, Path);
        finally
          Brush.Free;
        end;
        Graphics.ResetTransform;
      end;
      if FSettings.Outline then
      begin
        Graphics.TranslateTransform(Padding - Bounds.X, Padding - Bounds.Y);
        Pen := TGPPen.Create(GlyphColor(FSettings.OutlineColor, 255), FSettings.Stroke * 2);
        try
          Pen.SetLineJoin(LineJoinRound);
          Graphics.DrawPath(Pen, Path);
        finally
          Pen.Free;
        end;
      end;
    finally
      Graphics.Free;
    end;
    if FSettings.Outline or FSettings.Shadow then
      BlurDecoration(Result, Width, Height, FSettings.Blur,
        (FSettings.Outline and (ColorToRGB(FSettings.OutlineColor) <> clBlack)) or
        (FSettings.Shadow and (ColorToRGB(FSettings.ShadowColor) <> clBlack)));
    Graphics := TGPGraphics.Create(Result);
    try
      Graphics.SetSmoothingMode(SmoothingModeAntiAlias);
      Graphics.TranslateTransform(Padding - Bounds.X, Padding - Bounds.Y);
      Brush := TGPSolidBrush.Create(GlyphColor(FSettings.Color, 255));
      try
        Graphics.FillPath(Brush, Path);
      finally
        Brush.Free;
      end;
    finally
      Graphics.Free;
    end;
  finally
    Path.Free;
  end;
end;

function TNicomeaRenderer.Glyph(Index: Integer): TGPBitmap;
var
  Old: TGPBitmap;
  Key, CacheIndex: Integer;
  Size: Int64;
begin
  CacheIndex := Index;
  if FCells[Index].IsSeparator then CacheIndex := SEPARATOR_CACHE_INDEX;
  if FCache.TryGetValue(CacheIndex, Result) then Exit;
  Result := BuildGlyph(FCells[Index]);
  Size := Int64(Result.GetWidth) * Result.GetHeight * 4;
  while (FCacheOrder.Count > 0) and (FCacheBytes + Size > CACHE_BUDGET) do
  begin
    Key := FCacheOrder.Dequeue;
    Old := FCache[Key];
    Dec(FCacheBytes, Int64(Old.GetWidth) * Old.GetHeight * 4);
    FCache.Remove(Key);
  end;
  FCache.Add(CacheIndex, Result);
  FCacheOrder.Enqueue(CacheIndex);
  Inc(FCacheBytes, Size);
end;

function TNicomeaRenderer.FirstVisible(Threshold, Page: Integer): Integer;
var
  Hi, Mid, Limit: Integer;
begin
  Result := 0;
  Hi := Length(FCells);
  while Result < Hi do
  begin
    Mid := (Result + Hi) div 2;
    case FSettings.Style of
      nsHorizontal: Limit := FCells[Mid].X + FCells[Mid].Width + FGlyphMargin;
      nsVertical: Limit := FCells[Mid].Y + FRowHeight + FGlyphMargin;
    else
      Limit := FCells[Mid].Page;
    end;
    if FSettings.Style = nsPages then Threshold := Page;
    if Limit < Threshold then Result := Mid + 1
    else Hi := Mid;
  end;
end;

procedure TNicomeaRenderer.Draw(Target: TGPGraphics; const Destination: TRect; Progress: Double);
var
  State: GraphicsState;
  I, W, H, DX, DY, Page, First: Integer;
  X, Y: Integer;
  Image: TGPBitmap;
begin
  if Destination.IsEmpty or not HasContent then Exit;
  Progress := EnsureRange(Progress, 0.0, 1.0);
  W := FSettings.Area.Width;
  H := FSettings.Area.Height;
  DX := 0;
  DY := 0;
  Page := 0;
  case FSettings.Style of
    nsHorizontal: DX := Round(W - Progress * (W + FSpan));
    nsVertical: DY := Round(H - Progress * (H + FSpan));
    nsPages:
      begin
        Page := Min(FPageCount - 1, Floor(Progress * FPageCount));
        I := FirstVisible(0, Page + 1) - 1;
        DY := Max(0, (H - FCells[I].Y - FRowHeight) div 2);
      end;
  end;
  if FSettings.Style = nsHorizontal then
    First := FirstVisible(-DX, Page)
  else
    First := FirstVisible(-DY, Page);
  State := Target.Save;
  try
    Target.SetClip(MakeRect(Destination.Left, Destination.Top,
      Destination.Width, Destination.Height), CombineModeIntersect);
    Target.TranslateTransform(Destination.Left, Destination.Top);
    Target.ScaleTransform(Destination.Width / W, Destination.Height / H);
    Target.SetInterpolationMode(InterpolationModeHighQualityBicubic);
    for I := First to High(FCells) do
    begin
      X := FCells[I].X + DX;
      Y := FCells[I].Y + DY + (FRowHeight - FCells[I].Height) div 2;
      if FSettings.Style = nsHorizontal then Inc(Y, (H - FRowHeight) div 2);
      if (X - FGlyphMargin >= W) and (FSettings.Style = nsHorizontal) then Break;
      if (Y - FGlyphMargin >= H) and (FSettings.Style = nsVertical) then Break;
      if FCells[I].Page <> Page then Break;
      if (X + FCells[I].Width + FGlyphMargin <= 0) or
        (Y + FCells[I].Height + FGlyphMargin <= 0) then Continue;
      Image := Glyph(I);
      Target.DrawImage(Image, X - FGlyphMargin, Y - FGlyphMargin,
        FCells[I].Width + 2 * FGlyphMargin, FCells[I].Height + 2 * FGlyphMargin);
    end;
  finally
    Target.Restore(State);
  end;
end;

function TNicomeaRenderer.RenderSurface(const Destination, Clipped: TRect; Progress: Double): TGPBitmap;
var
  Graphics: TGPGraphics;
  Local: TRect;
begin
  if Clipped.IsEmpty then Exit(nil);
  if (FSurface = nil) or (Integer(FSurface.GetWidth) <> Clipped.Width) or
    (Integer(FSurface.GetHeight) <> Clipped.Height) then
  begin
    FreeAndNil(FSurface);
    FSurface := TGPBitmap.Create(Clipped.Width, Clipped.Height, PixelFormat32bppPARGB);
  end;
  Local := Destination;
  Local.Offset(-Clipped.Left, -Clipped.Top);
  Graphics := TGPGraphics.Create(FSurface);
  try
    Graphics.Clear(0);
    Draw(Graphics, Local, Progress);
  finally
    Graphics.Free;
  end;
  Result := FSurface;
end;

function TNicomeaRenderer.HasContent: Boolean;
begin
  Result := Length(FCells) > 0;
end;

end.
