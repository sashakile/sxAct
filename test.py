from wolframclient.evaluation import WolframLanguageSession

from wolframclient.language import wl, wlexpr
from pathlib import Path

path = Path("C:\\Program Files\\Wolfram Research\\Wolfram Engine\\12.1\\AddOns\\Applications\\xAct\\xTensor\\xTensorTests.nb")
session = WolframLanguageSession()
expr = f'''Off[FrontEndObject::notavail]
UsingFrontEnd[
NotebookImport[
     "{path.as_posix()}",
     "Input" -> "InpuptText" 
     ]
]'''
x = session.evaluate(wlexpr(expr))

session.terminate()