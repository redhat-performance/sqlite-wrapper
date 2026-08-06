import pydantic
import datetime

class sqlite_Results (pydantic.BaseModel):
    table_entries: int = pydantic.Field(gt=0)
    procs: int = pydantic.Field(gt=0)
    Real_time: float = pydantic.Field(gt=0, allow_inf_nan=False)
    User_time: float = pydantic.Field(ge=0, allow_inf_nan=False)
    System_time: float = pydantic.Field(ge=0, allow_inf_nan=False)
    Start_Date: datetime.datetime
    End_Date: datetime.datetime
