pragma solidty >= 0.5.0 <0.9.0;
contract course
{
    string name;
    uint code;
    contructor()
    {
        name = "Blockchain";
        code = 123;
    }
    function getName() view public returns(string memory)
    {
        return name;
    }
    function getCode() view public returns(uint)
    {
        return code;
    }
    function setName(string memory _name) public
    {
        name = _name;
    }
    function setCode(uint _code) public
    {
        code = _code;
    }
}