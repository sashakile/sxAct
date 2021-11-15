from wolframclient.evaluation import WolframLanguageSession
from wolframclient.language import expression, wl, wlexpr

session = WolframLanguageSession()
basePath = "C:\\Program Files\\Wolfram Research\\Wolfram Engine\\12.1\\AddOns\\Applications\\"

notebookPath = "xAct\\xTensor\\xTensorTests.nb"
# notebookPath = "xAct\\xCore\\xCore.nb"

expr = f'''Off[FrontEndObject::notavail]
UsingFrontEnd[NotebookImport["{basePath + notebookPath}", "Input"->"InputText"]]
'''.strip()

notebook = session.evaluate(wlexpr(expr))

for cell in notebook:
    wlexpression = wlexpr(cell)
    session.evaluate(wlexpression)

session.terminate()