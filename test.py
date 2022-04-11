import os
from wolframclient.evaluation import WolframLanguageSession

from wolframclient.language import wl, wlexpr
from pathlib import Path

KERNEL_PATH = Path( os.getenv("WOLFRAM_PATH") ) / "WolframKernel.exe"

path = Path("C:\\Program Files\\Wolfram Research\\Wolfram Engine\\12.1\\AddOns\\Applications\\xAct\\xTensor\\xTensorTests.nb")
session = WolframLanguageSession(KERNEL_PATH)
expr = f'''Off[FrontEndObject::notavail]
UsingFrontEnd[
NotebookImport[
     "{path.as_posix()}",
     "Input" -> "InpuptText" 
     ]
]'''
x = session.evaluate(wlexpr(expr))

session.terminate()