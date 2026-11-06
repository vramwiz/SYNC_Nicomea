unit SYNC_Nicomea_History;

// ニコニコ動画IDの正規化と、広告・ギフト履歴を順に取得するワーカー。
interface

uses
  System.Classes, System.JSON, System.SyncObjs, System.Net.HttpClient;

type
  TNicomeaHistoryKind = (nhAdvertising, nhGifts);

  TNicomeaHistoryEntry = record
    Timestamp, UserID, HistoryID: Int64;
    Name: string;
    ItemName, MessageText: string;
    Points, Contribution: Int64;
  end;

  TNicomeaHistory = TArray<TNicomeaHistoryEntry>;

  TNicomeaHistoryRequest = class(TThread)
  private
    FVideoID: string;
    FLog: TStringList;
    FLogLock: TCriticalSection;
    FHistory: array[TNicomeaHistoryKind] of TNicomeaHistory;
    FSuccessful: set of TNicomeaHistoryKind;
    procedure Log(const Message: string);
    function Fetch(Client: THTTPClient; Kind: TNicomeaHistoryKind): TNicomeaHistory;
    function FetchHistory(Client: THTTPClient; Kind: TNicomeaHistoryKind): Boolean;
  protected
    procedure Execute; override;
  public
    // 正規化済みの動画IDを受け取り、呼び出し側がStartするまで待機する。
    constructor Create(const VideoID: string);
    destructor Destroy; override;
    // 別スレッドから呼び出せる。未表示のログを末尾に追加してキューを空にする。
    procedure DrainLog(Destination: TStrings);
    // スレッド終了後に参照できる。失敗した種類は空の配列を返す。
    function History(Kind: TNicomeaHistoryKind): TNicomeaHistory;
    function Succeeded(Kind: TNicomeaHistoryKind): Boolean;
  end;

// 動画ID、視聴URL、共有用の短縮URLからIDを返す。解釈できない入力は空文字を返す。
function NormalizeNicomeaVideoID(const Input: string): string;

// 取得済み履歴をJSON項目に変換する。返した配列は呼び出し側で所有する。
function NicomeaHistoryToJSON(const History: TNicomeaHistory;
  Kind: TNicomeaHistoryKind): TJSONArray;
// JSON項目から履歴を復元する。Arrayの所有権は呼び出し側に残る。
function NicomeaHistoryFromJSON(Items: TJSONArray;
  Kind: TNicomeaHistoryKind): TNicomeaHistory;

implementation

uses
  System.Generics.Collections, System.Net.URLClient,
  System.NetConsts, System.RegularExpressions, System.SysUtils;

const
  HISTORY_NAMES: array[TNicomeaHistoryKind] of string = ('広告', 'ギフト');
  HISTORY_URLS: array[TNicomeaHistoryKind] of string = (
    'https://api.nicoad.nicovideo.jp/v3/contents/video/%s/histories?limit=100',
    'https://api.koken.nicovideo.jp/v1/userperspective/contents/gift/video/%s/histories?limit=30');
  CURSOR_PARAMS: array[TNicomeaHistoryKind] of string = ('offsetAdId', 'offsetId');
  CURSOR_KEYS: array[TNicomeaHistoryKind] of string = ('nicoadId', 'id');
  MAX_PAGES = 1000;
  WINHTTP_TIMEOUT = '(12002)';

function NormalizeNicomeaVideoID(const Input: string): string;
const
  PATTERN = '^(?:(?:https?://)?(?:(?:[a-z0-9-]+\.)?nicovideo\.jp/(?:watch|shorts?)/|nico\.ms/))?' +
    '((?:[a-z]{2})?[0-9]{1,20})/?(?:[?#]\S*)?$';
var
  Match: TMatch;
begin
  Match := TRegEx.Match(LowerCase(Trim(StringReplace(Input, #$3000, ' ', [rfReplaceAll]))),
    PATTERN);
  Result := '';
  if Match.Success then
    Result := Match.Groups[1].Value;
end;

function JSONText(Obj: TJSONObject; const Key: string): string;
var
  Value: TJSONValue;
begin
  Value := Obj.GetValue(Key);
  Result := '';
  if (Value is TJSONString) or (Value is TJSONNumber) then
    Result := Value.Value;
end;

function JSONNumber(Obj: TJSONObject; const Key: string): Int64;
begin
  Result := StrToInt64Def(JSONText(Obj, Key), 0);
end;

function ParseEntry(Obj: TJSONObject; Kind: TNicomeaHistoryKind): TNicomeaHistoryEntry;
begin
  Result := Default(TNicomeaHistoryEntry);
  if Kind = nhAdvertising then
  begin
    Result.Timestamp := JSONNumber(Obj, 'startedAt');
    Result.Name := JSONText(Obj, 'advertiserName');
    Result.Points := JSONNumber(Obj, 'adPoint');
    Result.UserID := JSONNumber(Obj, 'userId');
    Result.HistoryID := JSONNumber(Obj, 'nicoadId');
    Result.Contribution := JSONNumber(Obj, 'contribution');
    Result.MessageText := JSONText(Obj, 'message');
  end
  else
  begin
    Result.Timestamp := JSONNumber(Obj, 'publishedAt');
    Result.Name := JSONText(Obj, 'supporterName');
    Result.ItemName := JSONText(Obj, 'itemName');
    Result.Points := JSONNumber(Obj, 'point');
    Result.UserID := JSONNumber(Obj, 'supporterId');
    Result.HistoryID := JSONNumber(Obj, 'id');
    Result.Contribution := JSONNumber(Obj, 'contribution');
  end;
end;

function NicomeaHistoryToJSON(const History: TNicomeaHistory;
  Kind: TNicomeaHistoryKind): TJSONArray;
var
  Entry: TNicomeaHistoryEntry;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Entry in History do
    begin
      Item := TJSONObject.Create;
      Result.AddElement(Item);
      if Kind = nhAdvertising then
      begin
        Item.AddPair('startedAt', Entry.Timestamp);
        Item.AddPair('advertiserName', Entry.Name);
        Item.AddPair('adPoint', Entry.Points);
        Item.AddPair('userId', Entry.UserID);
        Item.AddPair('nicoadId', Entry.HistoryID);
        Item.AddPair('contribution', Entry.Contribution);
        Item.AddPair('message', Entry.MessageText);
      end
      else
      begin
        Item.AddPair('publishedAt', Entry.Timestamp);
        Item.AddPair('supporterName', Entry.Name);
        Item.AddPair('itemName', Entry.ItemName);
        Item.AddPair('point', Entry.Points);
        Item.AddPair('supporterId', Entry.UserID);
        Item.AddPair('id', Entry.HistoryID);
        Item.AddPair('contribution', Entry.Contribution);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function NicomeaHistoryFromJSON(Items: TJSONArray;
  Kind: TNicomeaHistoryKind): TNicomeaHistory;
var
  Item: TJSONValue;
  Count: Integer;
begin
  SetLength(Result, Items.Count);
  Count := 0;
  for Item in Items do
    if Item is TJSONObject then
    begin
      Result[Count] := ParseEntry(TJSONObject(Item), Kind);
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

constructor TNicomeaHistoryRequest.Create(const VideoID: string);
begin
  inherited Create(True);
  FVideoID := VideoID;
  FLog := TStringList.Create;
  FLogLock := TCriticalSection.Create;
end;

destructor TNicomeaHistoryRequest.Destroy;
begin
  // TThreadのデストラクタでワーカーを停止してからログを解放する。
  inherited;
  FLogLock.Free;
  FLog.Free;
end;

procedure TNicomeaHistoryRequest.Log(const Message: string);
begin
  FLogLock.Acquire;
  try
    FLog.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Message);
  finally
    FLogLock.Release;
  end;
end;

procedure TNicomeaHistoryRequest.DrainLog(Destination: TStrings);
begin
  FLogLock.Acquire;
  try
    if FLog.Count = 0 then Exit;
    Destination.AddStrings(FLog);
    FLog.Clear;
  finally
    FLogLock.Release;
  end;
end;

function TNicomeaHistoryRequest.History(Kind: TNicomeaHistoryKind): TNicomeaHistory;
begin
  Result := FHistory[Kind];
end;

function TNicomeaHistoryRequest.Succeeded(Kind: TNicomeaHistoryKind): Boolean;
begin
  Result := Kind in FSuccessful;
end;

function TNicomeaHistoryRequest.Fetch(Client: THTTPClient;
  Kind: TNicomeaHistoryKind): TNicomeaHistory;
var
  BaseURL, URL: string;
  Response: IHTTPResponse;
  Root, Value, Item: TJSONValue;
  Data: TJSONObject;
  Histories: TJSONArray;
  Entries: TList<TNicomeaHistoryEntry>;
  Cursors: TList<Int64>;
  Cursor, NextCount, Status: Int64;
begin
  Result := nil;
  BaseURL := Format(HISTORY_URLS[Kind], [FVideoID]);
  URL := BaseURL;
  Entries := TList<TNicomeaHistoryEntry>.Create;
  Cursors := TList<Int64>.Create;
  try
    repeat
      if Terminated then Exit;
      Log(Format('%sを取得中（%dページ目）', [HISTORY_NAMES[Kind], Cursors.Count + 1]));
      Response := Client.Get(URL);
      if Terminated then Exit;
      if Response.StatusCode <> 200 then
        raise Exception.CreateFmt('HTTP %d %s', [Response.StatusCode, Response.StatusText]);
      Root := TJSONObject.ParseJSONValue(Response.ContentAsString(TEncoding.UTF8));
      try
        if not (Root is TJSONObject) then
          raise Exception.Create('JSON応答を読み取れませんでした。');
        Value := TJSONObject(Root).GetValue('meta');
        if Value is TJSONObject then
        begin
          Status := JSONNumber(TJSONObject(Value), 'status');
          if Status <> 200 then
            raise Exception.CreateFmt('APIステータス %d', [Status]);
        end;
        Value := TJSONObject(Root).GetValue('data');
        if not (Value is TJSONObject) then
          raise Exception.Create('応答に履歴データがありません。');
        Data := TJSONObject(Value);
        Value := Data.GetValue('histories');
        if (Value = nil) and (Kind = nhGifts) then
          Value := Data.GetValue('items');
        if (Value = nil) and (Kind = nhGifts) then
          Value := Data.GetValue('gifts');
        if not (Value is TJSONArray) then
          raise Exception.Create('応答の履歴一覧を読み取れませんでした。');
        Histories := TJSONArray(Value);
        for Item in Histories do
        begin
          if not (Item is TJSONObject) then
            raise Exception.Create('履歴の項目を読み取れませんでした。');
          Entries.Add(ParseEntry(TJSONObject(Item), Kind));
        end;
        NextCount := JSONNumber(Data, 'nextCount');
        if NextCount > 0 then
        begin
          if Histories.Count = 0 then
            raise Exception.Create('次ページの開始位置がありません。');
          Cursor := JSONNumber(TJSONObject(Histories.Items[Histories.Count - 1]), CURSOR_KEYS[Kind]);
          if (Cursor <= 0) or Cursors.Contains(Cursor) then
            raise Exception.Create('次ページの開始位置が更新されませんでした。');
          if Cursors.Count + 1 >= MAX_PAGES then
            raise Exception.Create('ページ数の上限に達しました。');
          Cursors.Add(Cursor);
          URL := BaseURL + '&' + CURSOR_PARAMS[Kind] + '=' + IntToStr(Cursor);
        end;
      finally
        Root.Free;
      end;
    until NextCount <= 0;
    Result := Entries.ToArray;
  finally
    Cursors.Free;
    Entries.Free;
  end;
end;

function TNicomeaHistoryRequest.FetchHistory(Client: THTTPClient;
  Kind: TNicomeaHistoryKind): Boolean;
begin
  Result := False;
  if Terminated then Exit;
  try
    FHistory[Kind] := Fetch(Client, Kind);
    if Terminated then Exit;
    Include(FSuccessful, Kind);
    Log(Format('%s - 成功（%d件）', [HISTORY_NAMES[Kind], Length(FHistory[Kind])]));
    Result := True;
  except
    on E: Exception do
      if not Terminated then
      begin
        // WinHTTPの例外メッセージにはロケールに関係なくエラー番号が入る。
        if (E is ENetException) and E.Message.Contains(WINHTTP_TIMEOUT) then
          Log(HISTORY_NAMES[Kind] + ' - 失敗（通信タイムアウト）')
        else
          Log(HISTORY_NAMES[Kind] + ' - 失敗（' + E.Message + '）');
      end;
  end;
end;

procedure TNicomeaHistoryRequest.Execute;
var
  Client: THTTPClient;
  AdvertisingOK, GiftsOK: Boolean;
begin
  Log(FVideoID + ' の取得を開始');
  try
    Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := 5000;
      Client.SendTimeout := 5000;
      Client.ResponseTimeout := 10000;
      Client.HandleRedirects := False;
      Client.Accept := 'application/json';
      AdvertisingOK := FetchHistory(Client, nhAdvertising);
      GiftsOK := FetchHistory(Client, nhGifts);
    finally
      Client.Free;
    end;

    if Terminated then
      Log('取得を中止しました。')
    else if AdvertisingOK and GiftsOK then
      Log('取得完了 - 成功')
    else
      Log('取得完了 - 失敗');
  except
    on E: Exception do
      Log('取得完了 - 失敗（' + E.Message + '）');
  end;
end;

end.
