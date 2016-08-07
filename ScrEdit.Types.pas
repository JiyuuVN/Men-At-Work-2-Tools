unit ScrEdit.Types;

interface

const
  prmExtract = '-e';
  prmPatch = '-p';
  prmFileName = '-f';
  prmOutput = '-o';

  scrSignature = $31465342; // 'BSF1'

type
  TScrStringProlog = array[0..2] of Byte;

  TScrLocString = record
    value: string;
    origLen: Cardinal;
  end;
  TScrLocStrings = TArray<TScrLocString>;

  TScrStringData = record
    data: string;
    prolog: TScrStringProlog;
    offset: Cardinal;
  end;

  TScrDlgString = record
    data: TScrLocString;
    offset: Cardinal;
  end;

  TScrHeaderString = record
    data: TScrLocString;
    offsets: TArray<Cardinal>;
  end;

  TScrChooseDlg = record
    choices: TScrLocStrings;
    offset: Cardinal;
  end;

  TScrStrings = record
    dlgStrings: TArray<TScrDlgString>;
    headers: TArray<TScrHeaderString>;
    chooseDlg: TArray<TScrChooseDlg>;
  end;

  TScrLabelData = record
    name: string;
    addr: UInt32;
    scrOffset: UInt32;
  end;
  TScrLabels = TArray<TScrLabelData>;

implementation

end.
