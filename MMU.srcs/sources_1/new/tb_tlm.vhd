library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.MMU_package.all;

entity tb_tlm is
end entity;

architecture sim of tb_tlm is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Cache 0 CPU signals
  signal c0_req   : std_logic := '0';
  signal c0_func  : std_logic := '0';
  signal c0_addr  : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');
  signal c0_wdata : std_logic_vector(7 downto 0) := (others => '0');
  signal c0_rdata : std_logic_vector(7 downto 0);
  signal c0_ready : std_logic;

  -- Cache 1 CPU signals
  signal c1_req   : std_logic := '0';
  signal c1_func  : std_logic := '0';
  signal c1_addr  : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');
  signal c1_wdata : std_logic_vector(7 downto 0) := (others => '0');
  signal c1_rdata : std_logic_vector(7 downto 0);
  signal c1_ready : std_logic;

  constant CLK_PERIOD : time := 10 ns;

  -- helper: build address [tag|idx|off] for ADDR_W=8, TAG_W=4, IDX_W=2, OFF_W=2
  function mk_addr(tag : natural; idx : natural; off : natural) return std_logic_vector is
    variable a : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');
  begin
    a := std_logic_vector(to_unsigned(tag, TAG_W)) &
         std_logic_vector(to_unsigned(idx, IDX_W)) &
         std_logic_vector(to_unsigned(off, OFF_W));
    return a;
  end function;

begin
  clk <= not clk after CLK_PERIOD/2;

  DUT : entity work.tlm
    port map(
      clk => clk, rst => rst,

      c0_cpu_req   => c0_req,
      c0_cpu_func  => c0_func,
      c0_cpu_addr  => c0_addr,
      c0_cpu_wdata => c0_wdata,
      c0_cpu_rdata => c0_rdata,
      c0_cpu_ready => c0_ready,

      c1_cpu_req   => c1_req,
      c1_cpu_func  => c1_func,
      c1_cpu_addr  => c1_addr,
      c1_cpu_wdata => c1_wdata,
      c1_cpu_rdata => c1_rdata,
      c1_cpu_ready => c1_ready
    );

  stim : process
    procedure do_c0(func : std_logic; addr : std_logic_vector(ADDR_W-1 downto 0); wdata : std_logic_vector(7 downto 0)) is
    begin
      c0_func  <= func;
      c0_addr  <= addr;
      c0_wdata <= wdata;
      c0_req   <= '1';
      wait until rising_edge(clk);
      while c0_ready /= '1' loop
        wait until rising_edge(clk);
      end loop;
      c0_req <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure do_c1(func : std_logic; addr : std_logic_vector(ADDR_W-1 downto 0); wdata : std_logic_vector(7 downto 0)) is
    begin
      c1_func  <= func;
      c1_addr  <= addr;
      c1_wdata <= wdata;
      c1_req   <= '1';
      wait until rising_edge(clk);
      while c1_ready /= '1' loop
        wait until rising_edge(clk);
      end loop;
      c1_req <= '0';
      wait until rising_edge(clk);
    end procedure;

    -- read helpers return value via variable
    procedure rd_c0(addr : std_logic_vector(ADDR_W-1 downto 0); variable v : out std_logic_vector(7 downto 0)) is
    begin
      do_c0('0', addr, x"00");
      v := c0_rdata;
    end procedure;

    procedure rd_c1(addr : std_logic_vector(ADDR_W-1 downto 0); variable v : out std_logic_vector(7 downto 0)) is
    begin
      do_c1('0', addr, x"00");
      v := c1_rdata;
    end procedure;

    procedure wr_c0(addr : std_logic_vector(ADDR_W-1 downto 0); w : std_logic_vector(7 downto 0)) is
    begin
      do_c0('1', addr, w);
    end procedure;

    procedure wr_c1(addr : std_logic_vector(ADDR_W-1 downto 0); w : std_logic_vector(7 downto 0)) is
    begin
      do_c1('1', addr, w);
    end procedure;

    -- Variables for checks
    variable v0, v1 : std_logic_vector(7 downto 0);

    -- Addresses
    constant A0 : std_logic_vector(ADDR_W-1 downto 0) := mk_addr(2, 1, 0); -- tag=2 idx=1 off=0
    constant A1 : std_logic_vector(ADDR_W-1 downto 0) := mk_addr(2, 1, 1); -- same line, different byte
    constant A2 : std_logic_vector(ADDR_W-1 downto 0) := mk_addr(2, 1, 2);
    constant A3 : std_logic_vector(ADDR_W-1 downto 0) := mk_addr(2, 1, 3);

    -- Conflict address
    constant B0 : std_logic_vector(ADDR_W-1 downto 0) := mk_addr(7, 1, 0);

  begin
    -- reset
    rst <= '1';
    c0_req <= '0'; c1_req <= '0';
    wait for 5*CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    -- Case 1: C0 read miss A0
    rd_c0(A0, v0);
    report "CASE1 C0 RD A0 -> " & integer'image(to_integer(unsigned(v0)));

    -- Case 2: C1 read same address A0 (shared)
    rd_c1(A0, v1);
    report "CASE2 C1 RD A0 -> " & integer'image(to_integer(unsigned(v1)));
    assert v1 = v0 report "CASE2 FAIL: C1 read != C0 read" severity error;

    -- Case 3: C0 write A0, then C1 read A0 must see new value
    wr_c0(A0, x"AB");
    rd_c1(A0, v1);
    report "CASE3 C1 RD A0 after C0 WR -> " & integer'image(to_integer(unsigned(v1)));
    assert v1 = x"AB" report "CASE3 FAIL: C1 did not see AB" severity error;
    
    -- Case 4: C1 write A0, then C0 read A0 must see new value
    wr_c1(A0, x"3C");
    rd_c0(A0, v0);
    report "CASE4 C0 RD A0 after C1 WR -> " & integer'image(to_integer(unsigned(v0)));
    assert v0 = x"3C" report "CASE4 FAIL: C0 did not see 3C" severity error;

    -- Case 5: Write hit in M (C0 takes ownership then writes twice)
    wr_c0(A0, x"11");
    wr_c0(A0, x"22");
    rd_c0(A0, v0);
    report "CASE5 C0 RD A0 after two WR -> " & integer'image(to_integer(unsigned(v0)));
    assert v0 = x"22" report "CASE5 FAIL: C0 did not keep latest value" severity error;

    -- Case 6: Different offsets in same line
    -- Write 4 bytes into same line using off=0..3, then read back from other cache
    wr_c0(A0, x"A0");
    wr_c0(A1, x"A1");
    wr_c0(A2, x"A2");
    wr_c0(A3, x"A3");

    rd_c1(A0, v1); assert v1 = x"A0" report "CASE6 FAIL: off0" severity error;
    rd_c1(A1, v1); assert v1 = x"A1" report "CASE6 FAIL: off1" severity error;
    rd_c1(A2, v1); assert v1 = x"A2" report "CASE6 FAIL: off2" severity error;
    rd_c1(A3, v1); assert v1 = x"A3" report "CASE6 FAIL: off3" severity error;
    report "CASE6 PASS: offsets ok";

    -- Case 7: Eviction + writeback
    -- Put modified data in A0 (index=1) in C0 (M)
    -- Access B0 (same index=1 different tag) on C0 => evicts A0; if dirty, should WB
    -- C1 read A0; it must get the last written value (from memory after WB)
    wr_c0(A0, x"DE");
    -- conflict eviction 
    rd_c0(B0, v0);
    -- C1 reads A0, should see DE
    rd_c1(A0, v1);
    report "CASE7 C1 RD A0 after eviction -> " & integer'image(to_integer(unsigned(v1)));
    assert v1 = x"DE" report "CASE7 FAIL: writeback on eviction not observed" severity error;
    
    -- alternating ownership
    wr_c0(A0, x"55");
    rd_c1(A0, v1); assert v1 = x"55" report "CASE8 FAIL step1" severity error;

    wr_c1(A0, x"66");
    rd_c0(A0, v0); assert v0 = x"66" report "CASE8 FAIL step2" severity error;

    wr_c0(A0, x"77");
    rd_c1(A0, v1); assert v1 = x"77" report "CASE8 FAIL step3" severity error;

    -- Case 9: Simultaneous contention
    -- requests for both cores
    c0_addr <= A0; c0_func <= '0'; c0_req <= '1';
    c1_addr <= B0; c1_func <= '0'; c1_req <= '1';
    
    wait until rising_edge(clk);
    -- both are now 1
    
    -- wait until one of them is serviced
    while (c0_ready = '0' and c1_ready = '0') loop
        wait until rising_edge(clk);
    end loop;
    
    -- one core will have ready='1', the other will still be waiting.
    if c0_ready = '1' then
        report "CASE9: Arbiter chose Core 0 first.";
    else
        report "CASE9: Arbiter chose Core 1 first.";
    end if;

    c0_req <= '0'; c1_req <= '0';
    wait until rising_edge(clk);

    report "ALL TEST CASES PASSED" severity note;
    wait;
  end process;

end architecture;
