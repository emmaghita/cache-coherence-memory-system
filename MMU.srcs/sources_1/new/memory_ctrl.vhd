library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.MMU_package.all;

entity memory_ctrl is
  port (
    clk : in std_logic;
    rst : in std_logic;

    -- Cache 0 request in
    c0_bus_cmd_in  : in  bus_cmd_t;
    c0_bus_addr_in : in  std_logic_vector(ADDR_W-1 downto 0);
    c0_bus_data_in : in  std_logic_vector(DATA_W-1 downto 0); -- WB data if BUS_WB
    c0_bus_data_out: out std_logic_vector(DATA_W-1 downto 0); -- line data for RD/RDX
    c0_bus_ready   : out std_logic;
    c0_bus_shared  : out std_logic;

    -- Cache 0 snoop (MC -> C0), response (C0 -> MC)
    c0_snoop_cmd   : out bus_cmd_t;
    c0_snoop_addr  : out std_logic_vector(ADDR_W-1 downto 0);
    c0_snoop_valid : out std_logic;
    c0_snoop_data  : in  std_logic_vector(DATA_W-1 downto 0);
    c0_snoop_hit   : in  std_logic;

    -- Cache 1 request in
    c1_bus_cmd_in  : in  bus_cmd_t;
    c1_bus_addr_in : in  std_logic_vector(ADDR_W-1 downto 0);
    c1_bus_data_in : in  std_logic_vector(DATA_W-1 downto 0);
    c1_bus_data_out: out std_logic_vector(DATA_W-1 downto 0);
    c1_bus_ready   : out std_logic;
    c1_bus_shared  : out std_logic;

    -- Cache 1 snoop
    c1_snoop_cmd   : out bus_cmd_t;
    c1_snoop_addr  : out std_logic_vector(ADDR_W-1 downto 0);
    c1_snoop_valid : out std_logic;
    c1_snoop_data  : in  std_logic_vector(DATA_W-1 downto 0);
    c1_snoop_hit   : in  std_logic;

    -- Main memory interface (line-granular)
    mem_read     : out std_logic;
    mem_write    : out std_logic;
    mem_addr     : out std_logic_vector(ADDR_W-1 downto 0);
    mem_data_in  : out std_logic_vector(DATA_W-1 downto 0);
    mem_data_out : in  std_logic_vector(DATA_W-1 downto 0);
    mem_ready    : in  std_logic
  );
end entity;

architecture rtl of memory_ctrl is

  type owner_t is (OWN_NONE, OWN_C0, OWN_C1);
  type state_t is (IDLE, SNOOP, WAIT_SNOOP, MEMRD, MEMWB, RESP);

  signal st        : state_t := IDLE;
  signal owner     : owner_t := OWN_NONE;

  signal curr_cmd  : bus_cmd_t := BUS_NONE;
  signal curr_addr : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');
  signal curr_wb   : std_logic_vector(DATA_W-1 downto 0) := (others => '0');

  signal resp_data : std_logic_vector(DATA_W-1 downto 0) := (others => '0');
  signal shared_f  : std_logic := '0';

  -- round-robin pref
  signal prefer_c1 : std_logic := '0';

  -- for 32-bit line and byte addressing -> 2 offset bits
  constant OFFSET_BITS : integer := OFF_W;

  function align_to_line(a : std_logic_vector(ADDR_W-1 downto 0))
    return std_logic_vector is
    variable r : std_logic_vector(ADDR_W-1 downto 0);
  begin
    r := a;
    r(OFFSET_BITS-1 downto 0) := (others => '0');
    return r;
  end function;

begin

  process(clk)
    variable c0_req, c1_req : boolean;
    variable snoop_hit_v    : std_logic;
    variable snoop_data_v   : std_logic_vector(DATA_W-1 downto 0);
  begin
    if rising_edge(clk) then

      -- defaults each cycle
      c0_bus_ready   <= '0';
      c1_bus_ready   <= '0';
      c0_bus_shared  <= '0';
      c1_bus_shared  <= '0';

      c0_snoop_valid <= '0';
      c1_snoop_valid <= '0';
      c0_snoop_cmd   <= BUS_NONE;
      c1_snoop_cmd   <= BUS_NONE;
      c0_snoop_addr  <= (others => '0');
      c1_snoop_addr  <= (others => '0');

      mem_read       <= '0';
      mem_write      <= '0';
      mem_addr       <= (others => '0');
      mem_data_in    <= (others => '0');

      if rst = '1' then
        st        <= IDLE;
        owner     <= OWN_NONE;
        curr_cmd  <= BUS_NONE;
        curr_addr <= (others => '0');
        curr_wb   <= (others => '0');
        resp_data <= (others => '0');
        shared_f  <= '0';
        prefer_c1 <= '0';
        c0_bus_data_out <= (others => '0');
        c1_bus_data_out <= (others => '0');

      else
        -- request present
        c0_req := (c0_bus_cmd_in /= BUS_NONE);
        c1_req := (c1_bus_cmd_in /= BUS_NONE);

        -- snoop response from the other cache
        snoop_hit_v  := '0';
        snoop_data_v := (others => '0');
        if owner = OWN_C0 then
          snoop_hit_v  := c1_snoop_hit;
          snoop_data_v := c1_snoop_data;
        elsif owner = OWN_C1 then
          snoop_hit_v  := c0_snoop_hit;
          snoop_data_v := c0_snoop_data;
        end if;

        case st is

          when IDLE =>
            owner    <= OWN_NONE;
            curr_cmd <= BUS_NONE;
            shared_f <= '0';

            -- choose owner
            if c0_req and not c1_req then
              owner     <= OWN_C0;
              curr_cmd  <= c0_bus_cmd_in;
              curr_addr <= c0_bus_addr_in;
              curr_wb   <= c0_bus_data_in;
              prefer_c1 <= '1';
              -- next state decided below
              if c0_bus_cmd_in = BUS_WB then
                st <= MEMWB;
              else
                st <= SNOOP;
              end if;

            elsif c1_req and not c0_req then
              owner     <= OWN_C1;
              curr_cmd  <= c1_bus_cmd_in;
              curr_addr <= c1_bus_addr_in;
              curr_wb   <= c1_bus_data_in;
              prefer_c1 <= '0';
              if c1_bus_cmd_in = BUS_WB then
                st <= MEMWB;
              else
                st <= SNOOP;
              end if;

            elsif c0_req and c1_req then
              if prefer_c1='1' then
                owner     <= OWN_C1;
                curr_cmd  <= c1_bus_cmd_in;
                curr_addr <= c1_bus_addr_in;
                curr_wb   <= c1_bus_data_in;
                prefer_c1 <= '0';
                if c1_bus_cmd_in = BUS_WB then
                  st <= MEMWB;
                else
                  st <= SNOOP;
                end if;
              else
                owner     <= OWN_C0;
                curr_cmd  <= c0_bus_cmd_in;
                curr_addr <= c0_bus_addr_in;
                curr_wb   <= c0_bus_data_in;
                prefer_c1 <= '1';
                if c0_bus_cmd_in = BUS_WB then
                  st <= MEMWB;
                else
                  st <= SNOOP;
                end if;
              end if;
            end if;

          when SNOOP =>
            -- only RD/RDX cause snoop broadcasts
            if (curr_cmd = BUS_RD) or (curr_cmd = BUS_RDX) then
              if owner = OWN_C0 then
                c1_snoop_valid <= '1';
                c1_snoop_cmd   <= curr_cmd;
                c1_snoop_addr  <= curr_addr;
              elsif owner = OWN_C1 then
                c0_snoop_valid <= '1';
                c0_snoop_cmd   <= curr_cmd;
                c0_snoop_addr  <= curr_addr;
              end if;
              st <= WAIT_SNOOP;
            else
              -- unknown cmd
              st <= RESP;
            end if;

          when WAIT_SNOOP =>
            -- shared if other cache has it at all
            if snoop_hit_v = '1' then
              shared_f  <= '1';
              resp_data <= snoop_data_v; -- take data from other cache
              st        <= RESP;
            else
              mem_read <= '1';
              mem_addr <= align_to_line(curr_addr);
              st       <= MEMRD;
            end if;

          when MEMRD =>
            mem_read <= '1';
            mem_addr <= align_to_line(curr_addr);
            if mem_ready = '1' then
              resp_data <= mem_data_out;
              st        <= RESP;
            end if;

          when MEMWB =>
            mem_write   <= '1';
            mem_addr    <= align_to_line(curr_addr);
            mem_data_in <= curr_wb;
            if mem_ready = '1' then
              st <= RESP;
            end if;

          when RESP =>
            if owner = OWN_C0 then
              c0_bus_ready  <= '1';
              c0_bus_shared <= shared_f;
              if (curr_cmd = BUS_RD) or (curr_cmd = BUS_RDX) then
                c0_bus_data_out <= resp_data;
              end if;
            elsif owner = OWN_C1 then
              c1_bus_ready  <= '1';
              c1_bus_shared <= shared_f;
              if (curr_cmd = BUS_RD) or (curr_cmd = BUS_RDX) then
                c1_bus_data_out <= resp_data;
              end if;
            end if;

            -- done
            owner    <= OWN_NONE;
            curr_cmd <= BUS_NONE;
            shared_f <= '0';
            st       <= IDLE;

          when others =>
            st <= IDLE;

        end case;
      end if;
    end if;
  end process;

end architecture;
