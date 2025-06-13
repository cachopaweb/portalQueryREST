unit UnitPortalQueryREST.Component;

interface

uses
	System.Json,
	System.SysUtils,
	System.Classes,
	Data.DB,
	FireDAC.Comp.DataSet,
	FireDAC.Comp.Client,
	FireDAC.Stan.Param,   
  System.StrUtils, 
  System.Generics.Collections,
  UnitClientREST.Model.Interfaces;

type
  TPortalQueryREST = class(TFDMemTable)
	private
		FSQL   : TStrings;
		FParams: TFDParams;
		FSQLText  : string;
		{ Private declarations }
		procedure QueryChanged(Sender: TObject);
		function ParseSQL(const SQL: string; DoCreate: Boolean): string;
		function AddParameter: TFDParam;
		function GetParams: TFDParams;
		procedure SetSQL(const Value: TStrings);
    procedure ActiveCachedUpdates(const ADataSet: TDataSet; const AActive: Boolean);
	protected
		{ Protected declarations }
	public
		constructor Create(AOwner: TComponent); override;
		destructor Destroy; override;
		{ Public declarations }
	published
		{ Published declarations }
		property SQL   : TStrings read FSQL write SetSQL;
		property Params: TFDParams read GetParams write FParams;
		property SQLText  : string read FSQLText;
		/// //
		function ParamByName(Value: string): TFDParam;
		procedure OpenFromREST;
		function PostFromREST: Boolean;
    procedure ExecSQL;
    procedure Open;     
	end;

procedure Register;

implementation

{$IFDEF REST}

uses
	DataSet.Serialize,
  UnitClientREST.Model,
	UnitConfiguracaoServidor.Singleton, 
  UnitNavegadorWeb;
{$ENDIF}

procedure Register;
begin
	RegisterComponents('REST Client', [TPortalQueryREST]);
end;

function WordCount(Target, Input : String; IgnoreCase : Boolean) : Integer;
var
  SP : Integer;
  TempStr : String;

  function IsLetter(CH : Char) : Boolean;
  begin
    Result := (CH in ['a'..'z', 'A'..'Z']) or (CH = ':');
  end;

  function NextWord : String;
  begin
    Result := '';
    while (SP <= Length(Input)) and not (IsLetter(Input[SP])) do
      Inc(SP);

    while (SP <= Length(Input)) and IsLetter(Input[SP]) do begin
      Result := Result + Input[SP];
      Inc(SP);
    end;
  end;

begin
  Result := 0;
  if IgnoreCase then begin
    Target := LowerCase(Target);
    Input  := LowerCase(Input);
  end;

  SP := 1;
  repeat
    TempStr := NextWord;
    if TempStr = Target then
      inc(Result);
  until TempStr = '';
end;

procedure TPortalQueryREST.ActiveCachedUpdates(const ADataSet: TDataSet; const AActive: Boolean);
var
  LDataSet: TDataSet;
  LDataSetDetails: TObjectList<TDataSet>;
begin
  LDataSetDetails := TObjectList<TDataSet>.Create;
  try
    if not AActive then
      Self.Close;
    if ADataSet is TFDMemTable then
      TFDMemTable(ADataSet).CachedUpdates := AActive;
    if AActive and (not ADataSet.Active) and (ADataSet.FieldCount > 0) then
      ADataSet.Open;
    ADataSet.GetDetailDataSets(LDataSetDetails);
    for LDataSet in LDataSetDetails do
      ActiveCachedUpdates(LDataSet, AActive);
  finally
    LDataSetDetails.Free;
  end;
end;

function TPortalQueryREST.AddParameter: TFDParam;
begin
	Result := FParams.Add as TFDParam;
end;

constructor TPortalQueryREST.Create(AOwner: TComponent);
begin
	inherited Create(AOwner);
  FSQL                       := TStringList.Create;
	TStringList(FSQL).OnChange := QueryChanged;
	FParams                    := TFDParams.Create;  
end;

destructor TPortalQueryREST.Destroy;
begin
  if Assigned(FSQL) then
  	FSQL.DisposeOf;
  if Assigned(FParams) then
  	FParams.DisposeOf;
	inherited Destroy;
end;

procedure TPortalQueryREST.ExecSQL;
begin
//	try
		PostFromREST;
//  except

//  end;
end;

function TPortalQueryREST.GetParams: TFDParams;
begin
	if (FParams.Count = 0) then
		ParseSQL(FSQL.Text, True);
	Result := FParams;
end;

procedure TPortalQueryREST.Open;
begin
//	try
		OpenFromREST;
//  except

//  end;
end;

procedure TPortalQueryREST.OpenFromREST;
var
	{$IFDEF REST}
	Response   : TClientResult;
	{$ENDIF}
	aJson      : TJSONArray;
	ComandoSQL : string;
	i          : Integer;
	URLDataSets: string;
  Msg: TStringStream;
  Arquivo: string;
begin
	{$IFDEF REST}
	URLDataSets := TConfiguracaoServidor.BaseURL + '/dataset';
	ComandoSQL := ParseSQL(FSQL.Text, False);
	/// /
  Response := TClientREST.New(URLDataSets)
  											.AddHeader('Content-Type', 'application/json')
                        .AddBody(TJSONObject.Create.AddPair('sql', ComandoSQL))
                        .Post;    
  if Response.StatusCode = 200 then
  begin
  	ActiveCachedUpdates(Self, False);
    Self.LoadFromJSON(Response.Content);
    ActiveCachedUpdates(Self, True);    
  end
  else 
  begin
  	Msg := TStringStream.Create(Response.Content, TEncoding.UTF8);
  	try
    	Arquivo := ChangeFileExt(ExtractFileDir(ParamStr(0))+'\ERRO_REST', '.html');
      Msg.Position := 0;
      Msg.SaveToFile(Arquivo);
      FreeAndNil(FrmNavegadorWeb);
      if FrmNavegadorWeb = nil then
        FrmNavegadorWeb := TFrmNavegadorWeb.Create(nil, 'file://'+Arquivo);
      FrmNavegadorWeb.ShowModal;
    finally
      Msg.DisposeOf;      
    end;
    Abort;
  end;
  {$ENDIF}
end;

function TPortalQueryREST.ParamByName(Value: string): TFDParam;
begin
	try
		Result := Params.ParamByName(Value);
  except
  	ParseSQL(FSQL.Text, True);
    Result := Params.ParamByName(Value);
  end;
end;

function TPortalQueryREST.ParseSQL(const SQL: string; DoCreate: Boolean): string;

	function NameDelimiter(CurChar: Char): Boolean;
	begin
		case CurChar of
			' ', ',', ';', ')', #13, #10:
				Result := True;
		else
			Result := false;
		end;
	end;

var
	LiteralChar, CurChar                 : Char;
	CurPos, StartPos, BeginPos, NameStart: PChar;
	Name                                 : string;
	i                                    : Integer;
  Qtd: Integer;
  ValorParametro: string;
begin
	Result := '';

	if DoCreate then
		FParams.Clear;

	StartPos := PChar(SQL);
	BeginPos := StartPos;
	CurPos   := StartPos;
	while True do
	begin
		// Fast forward
		while True do
		begin
			case CurPos^ of
				#0, ':', '''', '"', '`':
					Break;
			end;
			Inc(CurPos);
		end;

		case CurPos^ of
			#0: // string end
				Break;
			'''', '"', '`': // literal
				begin
					LiteralChar := CurPos^;
					Inc(CurPos);
					// skip literal, escaped literal chars must not be handled because they
					// end the string and start a new string immediately.
					while (CurPos^ <> #0) and (CurPos^ <> LiteralChar) do
						Inc(CurPos);
					if CurPos^ = #0 then
						Break;
					Inc(CurPos);
				end;
			':': // parameter
				begin
					Inc(CurPos);
					if CurPos^ = ':' then
					begin
						Inc(CurPos); // skip escaped ":"
						Result   := Result + SQL.Substring(StartPos - BeginPos, CurPos - StartPos - 1);
						StartPos := CurPos;
					end
					else
					begin
						Result := Result + SQL.Substring(StartPos - BeginPos, CurPos - StartPos - 1) + '?';

						LiteralChar := #0;
						case CurPos^ of
							'''', '"', '`':
								begin
									LiteralChar := CurPos^;
									Inc(CurPos);
								end;
						end;
						NameStart := CurPos;

						CurChar := CurPos^;
						while CurChar <> #0 do
						begin
							if (CurChar = LiteralChar) or ((LiteralChar = #0) and NameDelimiter(CurChar)) then
								Break;
							Inc(CurPos);
							CurChar := CurPos^;
						end;
						SetString(Name, NameStart, CurPos - NameStart);
						if LiteralChar <> #0 then
							Inc(CurPos);
						if DoCreate then
							AddParameter.Name := Name;

						StartPos := CurPos;
					end;
				end;
		end;
	end;
	Result := Result + SQL.Substring(StartPos - BeginPos, CurPos - StartPos);
	// readjusting parameters
	Result := FSQL.Text;
	for i := 0 to Pred(FParams.Count) do
  begin
  	Qtd := WordCount(':' + FParams[i].Name, Result, true);     
    case TVarData(FParams[i].Value).vType of
    	varInteger: ValorParametro := Format('%d', [FParams[i].AsInteger]); 
    	varDouble, varCurrency:	ValorParametro := Format('%s', [FParams[i].AsString.Replace(',', '.')]);
      varDate:	ValorParametro := FormatDateTime('yyyy-mm-dd', FParams[i].AsDateTime);
    else
    	ValorParametro := FParams[i].AsString.Replace('/', '.').QuotedString;
    end;
  	if Qtd > 1  then//se tiver mais que um substitui todos
    	Result := Result.Replace(':' + FParams[i].Name, ValorParametro, [rfReplaceAll])
    else    
			Result := Result.Replace(':' + FParams[i].Name, ValorParametro, [rfIgnoreCase]);
  end;  
end;

function TPortalQueryREST.PostFromREST: Boolean;
var
	{$IFDEF REST}
  Response   : TClientResult;
  {$ENDIF}
	aJson      : TJSONArray;
	ComandoSQL : string;
	URLDataSets: string;
  url: string;
  Msg: TStringStream;
  Arquivo: string;
begin
	{$IFDEF REST}
	URLDataSets := TConfiguracaoServidor.BaseURL + '/dataset';
	ComandoSQL := ParseSQL(FSQL.Text, False);
	/// /
  Response := TClientREST.New(URLDataSets)
                        .AddHeader('Content-Type', 'application/json')
                        .AddBody(TJSONObject.Create.AddPair('sql', ComandoSQL))
                        .Post;
  Result   := Response.StatusCode = 200;
  if Response.StatusCode <> 200 then
  begin
  	Msg := TStringStream.Create(Response.Content, TEncoding.UTF8);
  	try
    	Arquivo := ChangeFileExt(ExtractFileDir(ParamStr(0))+'\ERRO_REST', '.html');
      Msg.Position := 0;
      Msg.SaveToFile(Arquivo);
      if FrmNavegadorWeb = nil then
        FrmNavegadorWeb := TFrmNavegadorWeb.Create(nil, 'file://'+Arquivo);
      FrmNavegadorWeb.ShowModal;
    finally
      Msg.DisposeOf;      
    end;
    Abort;
  end;
  {$ENDIF}
end;

procedure TPortalQueryREST.QueryChanged(Sender: TObject);
var
	List: TFDParams;
begin
	if not(csReading in ComponentState) then
	begin
		Disconnect;
		if (csDesigning in ComponentState) then
		begin
			List := TFDParams.Create;
			try
				FSQLText := ParseSQL(FSQL.Text, True);
				List.AssignValues(FParams);
				FParams.Clear;
				FParams.Assign(List);
			finally
				List.Free;
			end;
		end
		else
			FSQLText := FSQL.Text;
		DataEvent(dePropertyChange, 0);
	end
	else
		FSQLText := ParseSQL(FSQL.Text, false);
	SetSQL(FSQL);
end;

procedure TPortalQueryREST.SetSQL(const Value: TStrings);
begin
	if FSQL.Text <> Value.Text then
	begin
		FSQL.BeginUpdate;
		try
			FSQL.Assign(Value);
		finally
			FSQL.EndUpdate;
		end;
	end;
end;

end.
