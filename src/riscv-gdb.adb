-- ***************************************************************************
--              RISC-V Emulator - GDB Remote Stub
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************
with Ada.Text_IO;
with Ada.Strings.Fixed;
with RISCV.FPU;

package body RISCV.GDB is

   use Ada.Text_IO;

   --  Internal helpers
   function To_Hex        (V : Unsigned_8)   return String;
   function To_Hex_Word   (V : Word)         return String;
   function To_Hex_DWord  (V : Double_Word)  return String;
   function Parse_Hex     (S : String)       return Word;
   function Parse_Hex_DW  (S : String)       return Double_Word;
   function Calculate_Checksum (Data : String) return Unsigned_8;

   --  RV32 target description XML returned for qXfer:features:read:target.xml
   Target_XML : constant String :=
      "<?xml version=""1.0""?>" & ASCII.LF &
      "<!DOCTYPE target SYSTEM ""gdb-target.dtd"">" & ASCII.LF &
      "<target version=""1.0"">" & ASCII.LF &
      "  <architecture>riscv:rv32</architecture>" & ASCII.LF &
      "  <feature name=""org.gnu.gdb.riscv.cpu"">" & ASCII.LF &
      "    <reg name=""zero"" bitsize=""32"" regnum=""0""/>" & ASCII.LF &
      "    <reg name=""ra""   bitsize=""32"" type=""code_ptr"" regnum=""1""/>" & ASCII.LF &
      "    <reg name=""sp""   bitsize=""32"" type=""data_ptr"" regnum=""2""/>" & ASCII.LF &
      "    <reg name=""gp""   bitsize=""32"" regnum=""3""/>" & ASCII.LF &
      "    <reg name=""tp""   bitsize=""32"" regnum=""4""/>" & ASCII.LF &
      "    <reg name=""t0""   bitsize=""32"" regnum=""5""/>" & ASCII.LF &
      "    <reg name=""t1""   bitsize=""32"" regnum=""6""/>" & ASCII.LF &
      "    <reg name=""t2""   bitsize=""32"" regnum=""7""/>" & ASCII.LF &
      "    <reg name=""fp""   bitsize=""32"" type=""data_ptr"" regnum=""8""/>" & ASCII.LF &
      "    <reg name=""s1""   bitsize=""32"" regnum=""9""/>" & ASCII.LF &
      "    <reg name=""a0""   bitsize=""32"" regnum=""10""/>" & ASCII.LF &
      "    <reg name=""a1""   bitsize=""32"" regnum=""11""/>" & ASCII.LF &
      "    <reg name=""a2""   bitsize=""32"" regnum=""12""/>" & ASCII.LF &
      "    <reg name=""a3""   bitsize=""32"" regnum=""13""/>" & ASCII.LF &
      "    <reg name=""a4""   bitsize=""32"" regnum=""14""/>" & ASCII.LF &
      "    <reg name=""a5""   bitsize=""32"" regnum=""15""/>" & ASCII.LF &
      "    <reg name=""a6""   bitsize=""32"" regnum=""16""/>" & ASCII.LF &
      "    <reg name=""a7""   bitsize=""32"" regnum=""17""/>" & ASCII.LF &
      "    <reg name=""s2""   bitsize=""32"" regnum=""18""/>" & ASCII.LF &
      "    <reg name=""s3""   bitsize=""32"" regnum=""19""/>" & ASCII.LF &
      "    <reg name=""s4""   bitsize=""32"" regnum=""20""/>" & ASCII.LF &
      "    <reg name=""s5""   bitsize=""32"" regnum=""21""/>" & ASCII.LF &
      "    <reg name=""s6""   bitsize=""32"" regnum=""22""/>" & ASCII.LF &
      "    <reg name=""s7""   bitsize=""32"" regnum=""23""/>" & ASCII.LF &
      "    <reg name=""s8""   bitsize=""32"" regnum=""24""/>" & ASCII.LF &
      "    <reg name=""s9""   bitsize=""32"" regnum=""25""/>" & ASCII.LF &
      "    <reg name=""s10""  bitsize=""32"" regnum=""26""/>" & ASCII.LF &
      "    <reg name=""s11""  bitsize=""32"" regnum=""27""/>" & ASCII.LF &
      "    <reg name=""t3""   bitsize=""32"" regnum=""28""/>" & ASCII.LF &
      "    <reg name=""t4""   bitsize=""32"" regnum=""29""/>" & ASCII.LF &
      "    <reg name=""t5""   bitsize=""32"" regnum=""30""/>" & ASCII.LF &
      "    <reg name=""t6""   bitsize=""32"" regnum=""31""/>" & ASCII.LF &
      "    <reg name=""pc""   bitsize=""32"" type=""code_ptr"" regnum=""32""/>" & ASCII.LF &
      "  </feature>" & ASCII.LF &
      "</target>" & ASCII.LF;

   --  RV64 target description XML
   Target_XML_64 : constant String :=
      "<?xml version=""1.0""?>" & ASCII.LF &
      "<!DOCTYPE target SYSTEM ""gdb-target.dtd"">" & ASCII.LF &
      "<target version=""1.0"">" & ASCII.LF &
      "  <architecture>riscv:rv64</architecture>" & ASCII.LF &
      "  <feature name=""org.gnu.gdb.riscv.cpu"">" & ASCII.LF &
      "    <reg name=""zero"" bitsize=""64"" regnum=""0""/>" & ASCII.LF &
      "    <reg name=""ra""   bitsize=""64"" type=""code_ptr"" regnum=""1""/>" & ASCII.LF &
      "    <reg name=""sp""   bitsize=""64"" type=""data_ptr"" regnum=""2""/>" & ASCII.LF &
      "    <reg name=""gp""   bitsize=""64"" regnum=""3""/>" & ASCII.LF &
      "    <reg name=""tp""   bitsize=""64"" regnum=""4""/>" & ASCII.LF &
      "    <reg name=""t0""   bitsize=""64"" regnum=""5""/>" & ASCII.LF &
      "    <reg name=""t1""   bitsize=""64"" regnum=""6""/>" & ASCII.LF &
      "    <reg name=""t2""   bitsize=""64"" regnum=""7""/>" & ASCII.LF &
      "    <reg name=""fp""   bitsize=""64"" type=""data_ptr"" regnum=""8""/>" & ASCII.LF &
      "    <reg name=""s1""   bitsize=""64"" regnum=""9""/>" & ASCII.LF &
      "    <reg name=""a0""   bitsize=""64"" regnum=""10""/>" & ASCII.LF &
      "    <reg name=""a1""   bitsize=""64"" regnum=""11""/>" & ASCII.LF &
      "    <reg name=""a2""   bitsize=""64"" regnum=""12""/>" & ASCII.LF &
      "    <reg name=""a3""   bitsize=""64"" regnum=""13""/>" & ASCII.LF &
      "    <reg name=""a4""   bitsize=""64"" regnum=""14""/>" & ASCII.LF &
      "    <reg name=""a5""   bitsize=""64"" regnum=""15""/>" & ASCII.LF &
      "    <reg name=""a6""   bitsize=""64"" regnum=""16""/>" & ASCII.LF &
      "    <reg name=""a7""   bitsize=""64"" regnum=""17""/>" & ASCII.LF &
      "    <reg name=""s2""   bitsize=""64"" regnum=""18""/>" & ASCII.LF &
      "    <reg name=""s3""   bitsize=""64"" regnum=""19""/>" & ASCII.LF &
      "    <reg name=""s4""   bitsize=""64"" regnum=""20""/>" & ASCII.LF &
      "    <reg name=""s5""   bitsize=""64"" regnum=""21""/>" & ASCII.LF &
      "    <reg name=""s6""   bitsize=""64"" regnum=""22""/>" & ASCII.LF &
      "    <reg name=""s7""   bitsize=""64"" regnum=""23""/>" & ASCII.LF &
      "    <reg name=""s8""   bitsize=""64"" regnum=""24""/>" & ASCII.LF &
      "    <reg name=""s9""   bitsize=""64"" regnum=""25""/>" & ASCII.LF &
      "    <reg name=""s10""  bitsize=""64"" regnum=""26""/>" & ASCII.LF &
      "    <reg name=""s11""  bitsize=""64"" regnum=""27""/>" & ASCII.LF &
      "    <reg name=""t3""   bitsize=""64"" regnum=""28""/>" & ASCII.LF &
      "    <reg name=""t4""   bitsize=""64"" regnum=""29""/>" & ASCII.LF &
      "    <reg name=""t5""   bitsize=""64"" regnum=""30""/>" & ASCII.LF &
      "    <reg name=""t6""   bitsize=""64"" regnum=""31""/>" & ASCII.LF &
      "    <reg name=""pc""   bitsize=""64"" type=""code_ptr"" regnum=""32""/>" & ASCII.LF &
      "  </feature>" & ASCII.LF &
      "  <feature name=""org.gnu.gdb.riscv.fpu"">" & ASCII.LF &
      "    <reg name=""ft0""   bitsize=""64"" type=""ieee_double"" regnum=""33""/>" & ASCII.LF &
      "    <reg name=""ft1""   bitsize=""64"" type=""ieee_double"" regnum=""34""/>" & ASCII.LF &
      "    <reg name=""ft2""   bitsize=""64"" type=""ieee_double"" regnum=""35""/>" & ASCII.LF &
      "    <reg name=""ft3""   bitsize=""64"" type=""ieee_double"" regnum=""36""/>" & ASCII.LF &
      "    <reg name=""ft4""   bitsize=""64"" type=""ieee_double"" regnum=""37""/>" & ASCII.LF &
      "    <reg name=""ft5""   bitsize=""64"" type=""ieee_double"" regnum=""38""/>" & ASCII.LF &
      "    <reg name=""ft6""   bitsize=""64"" type=""ieee_double"" regnum=""39""/>" & ASCII.LF &
      "    <reg name=""ft7""   bitsize=""64"" type=""ieee_double"" regnum=""40""/>" & ASCII.LF &
      "    <reg name=""fs0""   bitsize=""64"" type=""ieee_double"" regnum=""41""/>" & ASCII.LF &
      "    <reg name=""fs1""   bitsize=""64"" type=""ieee_double"" regnum=""42""/>" & ASCII.LF &
      "    <reg name=""fa0""   bitsize=""64"" type=""ieee_double"" regnum=""43""/>" & ASCII.LF &
      "    <reg name=""fa1""   bitsize=""64"" type=""ieee_double"" regnum=""44""/>" & ASCII.LF &
      "    <reg name=""fa2""   bitsize=""64"" type=""ieee_double"" regnum=""45""/>" & ASCII.LF &
      "    <reg name=""fa3""   bitsize=""64"" type=""ieee_double"" regnum=""46""/>" & ASCII.LF &
      "    <reg name=""fa4""   bitsize=""64"" type=""ieee_double"" regnum=""47""/>" & ASCII.LF &
      "    <reg name=""fa5""   bitsize=""64"" type=""ieee_double"" regnum=""48""/>" & ASCII.LF &
      "    <reg name=""fa6""   bitsize=""64"" type=""ieee_double"" regnum=""49""/>" & ASCII.LF &
      "    <reg name=""fa7""   bitsize=""64"" type=""ieee_double"" regnum=""50""/>" & ASCII.LF &
      "    <reg name=""fs2""   bitsize=""64"" type=""ieee_double"" regnum=""51""/>" & ASCII.LF &
      "    <reg name=""fs3""   bitsize=""64"" type=""ieee_double"" regnum=""52""/>" & ASCII.LF &
      "    <reg name=""fs4""   bitsize=""64"" type=""ieee_double"" regnum=""53""/>" & ASCII.LF &
      "    <reg name=""fs5""   bitsize=""64"" type=""ieee_double"" regnum=""54""/>" & ASCII.LF &
      "    <reg name=""fs6""   bitsize=""64"" type=""ieee_double"" regnum=""55""/>" & ASCII.LF &
      "    <reg name=""fs7""   bitsize=""64"" type=""ieee_double"" regnum=""56""/>" & ASCII.LF &
      "    <reg name=""fs8""   bitsize=""64"" type=""ieee_double"" regnum=""57""/>" & ASCII.LF &
      "    <reg name=""fs9""   bitsize=""64"" type=""ieee_double"" regnum=""58""/>" & ASCII.LF &
      "    <reg name=""fs10""  bitsize=""64"" type=""ieee_double"" regnum=""59""/>" & ASCII.LF &
      "    <reg name=""fs11""  bitsize=""64"" type=""ieee_double"" regnum=""60""/>" & ASCII.LF &
      "    <reg name=""ft8""   bitsize=""64"" type=""ieee_double"" regnum=""61""/>" & ASCII.LF &
      "    <reg name=""ft9""   bitsize=""64"" type=""ieee_double"" regnum=""62""/>" & ASCII.LF &
      "    <reg name=""ft10""  bitsize=""64"" type=""ieee_double"" regnum=""63""/>" & ASCII.LF &
      "    <reg name=""ft11""  bitsize=""64"" type=""ieee_double"" regnum=""64""/>" & ASCII.LF &
      "    <reg name=""fflags"" bitsize=""32"" regnum=""65""/>" & ASCII.LF &
      "    <reg name=""frm""    bitsize=""32"" regnum=""66""/>" & ASCII.LF &
      "    <reg name=""fcsr""   bitsize=""32"" regnum=""67""/>" & ASCII.LF &
      "  </feature>" & ASCII.LF &
      "</target>" & ASCII.LF;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Server     : out GDB_Server;
                        Port       : Natural := 1234;
                        Listen_All : Boolean := False) is
   begin
      Server.Port := Port;
      Server.Connected := False;
      Server.No_Ack_Mode := False;
      Server.Num_Breakpoints := 0;

      Create_Socket (Server.Listening_Socket);
      Set_Socket_Option (Server.Listening_Socket,
                        Socket_Level,
                        (Reuse_Address, True));

      --  Loopback by default: RSP is unauthenticated and exposes the guest's
      --  whole address space to whoever connects.
      Server.Address.Addr :=
         (if Listen_All then Any_Inet_Addr else Loopback_Inet_Addr);
      Server.Address.Port := Port_Type (Port);
      Bind_Socket (Server.Listening_Socket, Server.Address);
      Listen_Socket (Server.Listening_Socket);

      if Listen_All then
         Put_Line ("GDB server listening on ALL interfaces, port" &
            Natural'Image (Port) & " (unauthenticated)");
      else
         Put_Line ("GDB server listening on 127.0.0.1 port" &
            Natural'Image (Port));
      end if;
   end Initialize;

   -----------------------
   -- Accept_Connection --
   -----------------------

   function Accept_Connection (Server : in out GDB_Server) return Boolean is
      Client_Addr : Sock_Addr_Type;
   begin
      Put_Line ("Waiting for GDB connection...");
      Accept_Socket (Server.Listening_Socket,
                    Server.Client_Socket,
                    Client_Addr);
      Server.Connected := True;
      Put_Line ("GDB connected from " & Image (Client_Addr));
      return True;
   exception
      when others =>
         Server.Connected := False;
         return False;
   end Accept_Connection;

   ------------------
   -- Is_Connected --
   ------------------

   function Is_Connected (Server : GDB_Server) return Boolean is
   begin
      return Server.Connected;
   end Is_Connected;

   -----------
   -- Close --
   -----------

   procedure Close (Server : in out GDB_Server) is
   begin
      if Server.Connected then
         Close_Socket (Server.Client_Socket);
         Server.Connected := False;
      end if;
      Close_Socket (Server.Listening_Socket);
   end Close;

   ------------------
   -- Is_Breakpoint --
   ------------------

   function Is_Breakpoint (Server : GDB_Server;
                           Addr   : Double_Word) return Boolean is
   begin
      for I in 1 .. Server.Num_Breakpoints loop
         if Server.Breakpoints (I) = Addr then
            return True;
         end if;
      end loop;
      return False;
   end Is_Breakpoint;

   function Is_Watchpoint_Hit (Server   : GDB_Server;
                                Addr     : Double_Word;
                                Is_Write : Boolean) return Boolean is
   begin
      for I in 1 .. Server.Num_Watchpoints loop
         if Server.Watchpoints (I).Valid and then
            Server.Watchpoints (I).Addr = Addr
         then
            case Server.Watchpoints (I).Kind is
               when Watch_Write  => if Is_Write  then return True; end if;
               when Watch_Read   => if not Is_Write then return True; end if;
               when Watch_Access => return True;
            end case;
         end if;
      end loop;
      return False;
   end Is_Watchpoint_Hit;

   --  ---- Internal helpers ----

   procedure Send_Packet (Server : in out GDB_Server; Data : String) is
      Checksum : constant Unsigned_8 := Calculate_Checksum (Data);
      Packet   : constant String := "$" & Data & "#" & To_Hex (Checksum);
      Channel  : Stream_Access;
   begin
      Channel := Stream (Server.Client_Socket);
      String'Write (Channel, Packet);
   end Send_Packet;

   function Receive_Packet (Server : in out GDB_Server) return String is
      Channel   : Stream_Access;
      C         : Character;
      Buffer    : String (1 .. 16384);
      Idx       : Natural := 0;
      In_Packet : Boolean := False;
   begin
      Channel := Stream (Server.Client_Socket);
      loop
         Character'Read (Channel, C);
         if C = '$' then
            In_Packet := True;
            Idx := 0;
         elsif C = '#' and In_Packet then
            --  Consume two checksum hex digits
            Character'Read (Channel, C);
            Character'Read (Channel, C);
            if not Server.No_Ack_Mode then
               String'Write (Channel, "+");
            end if;
            return Buffer (1 .. Idx);
         elsif In_Packet then
            Idx := Idx + 1;
            Buffer (Idx) := C;
         elsif C = Character'Val (3) then   -- Ctrl-C interrupt
            return "!interrupt";
         end if;
      end loop;
   end Receive_Packet;

   --  Return a slice of Data starting at Offset (0-based) with at most Len bytes.
   --  Prefix 'l' means last chunk, 'm' means more follows.
   function Xfer_Response (Data : String; Offset : Natural; Len : Natural)
      return String
   is
      Start : constant Natural := Data'First + Offset;
   begin
      if Start > Data'Last then
         return "l";  -- past end ->empty last chunk
      end if;
      declare
         Available : constant Natural := Data'Last - Start + 1;
         Chunk     : constant Natural := Natural'Min (Available, Len);
         Last      : constant Boolean := (Start + Chunk - 1 >= Data'Last);
      begin
         return (if Last then "l" else "m") & Data (Start .. Start + Chunk - 1);
      end;
   end Xfer_Response;

   --  Handle Z (insert) / z (remove) breakpoint or watchpoint packet.
   --  Shared between RV32 and RV64 variants.
   procedure Handle_Z_Packet (Server : in out GDB_Server;
                               Packet : String;
                               Insert : Boolean) is
      Kind_Ch : constant Character :=
         (if Packet'Length > 1 then Packet (Packet'First + 1) else '?');
      Comma1 : constant Natural :=
         Ada.Strings.Fixed.Index (Packet, ",");
   begin
      if Comma1 = 0 then
         Send_Packet (Server, "");
         return;
      end if;

      declare
         Comma2 : Natural := 0;
      begin
         for I in Comma1 + 1 .. Packet'Last loop
            if Packet (I) = ',' then Comma2 := I; exit; end if;
         end loop;
         declare
            Addr_End : constant Natural :=
               (if Comma2 > 0 then Comma2 - 1 else Packet'Last);
            Addr : constant Double_Word :=
               Parse_Hex_DW (Packet (Comma1 + 1 .. Addr_End));
         begin
            if Kind_Ch = '0' then
               --  Software breakpoint
               if Insert then
                  if not Is_Breakpoint (Server, Addr) and then
                     Server.Num_Breakpoints < Max_Breakpoints
                  then
                     Server.Num_Breakpoints := Server.Num_Breakpoints + 1;
                     Server.Breakpoints (Server.Num_Breakpoints) := Addr;
                  end if;
               else
                  for I in 1 .. Server.Num_Breakpoints loop
                     if Server.Breakpoints (I) = Addr then
                        Server.Breakpoints (I ..
                           Server.Num_Breakpoints - 1) :=
                           Server.Breakpoints (I + 1 ..
                              Server.Num_Breakpoints);
                        Server.Num_Breakpoints :=
                           Server.Num_Breakpoints - 1;
                        exit;
                     end if;
                  end loop;
               end if;
               Send_Packet (Server, "OK");

            elsif Kind_Ch in '2' | '3' | '4' then
               --  Hardware watchpoint
               declare
                  WKind : constant Watchpoint_Kind :=
                     (case Kind_Ch is
                        when '2'    => Watch_Write,
                        when '3'    => Watch_Read,
                        when others => Watch_Access);
               begin
                  if Insert then
                     declare
                        Already : Boolean := False;
                     begin
                        for I in 1 .. Server.Num_Watchpoints loop
                           if Server.Watchpoints (I).Valid and then
                              Server.Watchpoints (I).Addr = Addr and then
                              Server.Watchpoints (I).Kind = WKind
                           then Already := True; end if;
                        end loop;
                        if not Already and then
                           Server.Num_Watchpoints < Max_Watchpoints
                        then
                           Server.Num_Watchpoints :=
                              Server.Num_Watchpoints + 1;
                           Server.Watchpoints (Server.Num_Watchpoints) :=
                              (Addr => Addr, Kind => WKind, Valid => True);
                        end if;
                     end;
                  else
                     for I in 1 .. Server.Num_Watchpoints loop
                        if Server.Watchpoints (I).Valid and then
                           Server.Watchpoints (I).Addr = Addr
                        then
                           Server.Watchpoints (I).Valid := False;
                           Server.Watchpoints (I ..
                              Server.Num_Watchpoints - 1) :=
                              Server.Watchpoints (I + 1 ..
                                 Server.Num_Watchpoints);
                           Server.Num_Watchpoints :=
                              Server.Num_Watchpoints - 1;
                           exit;
                        end if;
                     end loop;
                  end if;
               end;
               Send_Packet (Server, "OK");

            else
               Send_Packet (Server, "");   -- unsupported type
            end if;
         end;
      end;
   end Handle_Z_Packet;

   --  Handle all query ('q'/'Q') packets - identical for RV32 and RV64,
   --  parameterised by which target XML to serve.
   procedure Handle_Query (Server     : in out GDB_Server;
                           Packet     : String;
                           Target_Xml : String) is
   begin
      if Packet'Length >= 10 and then
         Packet (Packet'First .. Packet'First + 9) = "qSupported"
      then
         Send_Packet (Server,
            "PacketSize=4096" &
            ";qXfer:features:read+" &
            ";swbreak+" &
            ";hwbreak+" &
            ";Z2+;Z3+;Z4+" &
            ";vContSupported+");

      elsif Packet'Length >= 23 and then
         Packet (Packet'First .. Packet'First + 22) =
            "qXfer:features:read:tar"
      then
         declare
            Last_Colon : Natural := 0;
         begin
            for I in Packet'Range loop
               if Packet (I) = ':' then
                  Last_Colon := I;
               end if;
            end loop;

            if Last_Colon > 0 then
               declare
                  OL    : constant String :=
                     Packet (Last_Colon + 1 .. Packet'Last);
                  Comma : constant Natural :=
                     Ada.Strings.Fixed.Index (OL, ",");
               begin
                  if Comma > 0 then
                     declare
                        Offset : constant Natural :=
                           Natural (Parse_Hex
                              (OL (OL'First .. Comma - 1)));
                        Len    : constant Natural :=
                           Natural (Parse_Hex
                              (OL (Comma + 1 .. OL'Last)));
                     begin
                        Send_Packet (Server,
                           Xfer_Response (Target_Xml, Offset, Len));
                     end;
                  else
                     Send_Packet (Server, "l");
                  end if;
               end;
            else
               Send_Packet (Server, "l");
            end if;
         end;

      elsif Packet = "qAttached" then
         Send_Packet (Server, "1");
      elsif Packet = "qC" then
         Send_Packet (Server, "QC1");
      elsif Packet = "qfThreadInfo" then
         Send_Packet (Server, "m1");
      elsif Packet = "qsThreadInfo" then
         Send_Packet (Server, "l");
      else
         Send_Packet (Server, "");
      end if;
   end Handle_Query;

   -----------------------
   -- Process_Commands (RV32) --
   -----------------------

   procedure Process_Commands (Server      : in out GDB_Server;
                               CPU         : in out RISCV.CPU.CPU_State;
                               Mem         : in out RISCV.Memory.Memory_Unit;
                               Should_Run  : out Boolean;
                               Should_Step : out Boolean) is
      Packet : constant String := Receive_Packet (Server);
   begin
      Should_Run  := False;
      Should_Step := False;

      if Packet'Length = 0 then
         return;
      end if;

      if Packet = "!interrupt" then
         Send_Stop_Reply (Server, CPU, 2);   -- SIGINT
         return;
      end if;

      case Packet (Packet'First) is

         when '?' =>
            Send_Stop_Reply (Server, CPU, 5);   -- SIGTRAP

         --  ---- Register read (all) ----
         when 'g' =>
            declare
               Response : String (1 .. 33 * 8);
               Pos : Natural := 1;
            begin
               for I in 0 .. 31 loop
                  Response (Pos .. Pos + 7) :=
                     To_Hex_Word (CPU.Registers (Register_Index (I)));
                  Pos := Pos + 8;
               end loop;
               Response (Pos .. Pos + 7) := To_Hex_Word (CPU.PC);
               Send_Packet (Server, Response);
            end;

         --  ---- Register write (all) ----
         when 'G' =>
            declare
               Data : constant String :=
                  Packet (Packet'First + 1 .. Packet'Last);
            begin
               if Data'Length >= 32 * 8 then
                  for I in 0 .. 31 loop
                     declare
                        Pos : constant Natural := Data'First + I * 8;
                        Val : constant Word :=
                           Parse_Hex (Data (Pos .. Pos + 7));
                     begin
                        CPU.Registers (Register_Index (I)) := Val;
                     end;
                  end loop;
                  if Data'Length >= 33 * 8 then
                     declare
                        Pos : constant Natural := Data'First + 32 * 8;
                     begin
                        CPU.PC := Parse_Hex (Data (Pos .. Pos + 7));
                     end;
                  end if;
               end if;
               Send_Packet (Server, "OK");
            end;

         --  ---- Single register read ----
         when 'p' =>
            declare
               Reg : constant Natural :=
                  Natural (Parse_Hex (Packet (Packet'First + 1 .. Packet'Last)));
            begin
               if Reg <= 31 then
                  Send_Packet (Server,
                     To_Hex_Word (CPU.Registers (Register_Index (Reg))));
               elsif Reg = 32 then
                  Send_Packet (Server, To_Hex_Word (CPU.PC));
               else
                  Send_Packet (Server, "xxxxxxxx");
               end if;
            end;

         --  ---- Single register write ----
         when 'P' =>
            declare
               Eq : constant Natural :=
                  Ada.Strings.Fixed.Index (Packet, "=");
            begin
               if Eq > 0 then
                  declare
                     Reg : constant Natural :=
                        Natural (Parse_Hex
                           (Packet (Packet'First + 1 .. Eq - 1)));
                     Val : constant Word :=
                        Parse_Hex (Packet (Eq + 1 .. Packet'Last));
                  begin
                     if Reg <= 31 then
                        CPU.Registers (Register_Index (Reg)) := Val;
                     elsif Reg = 32 then
                        CPU.PC := Val;
                     end if;
                  end;
               end if;
               Send_Packet (Server, "OK");
            end;

         --  ---- Memory read ----
         when 'm' =>
            declare
               Comma : constant Natural :=
                  Ada.Strings.Fixed.Index (Packet, ",");
            begin
               if Comma > 0 then
                  declare
                     Addr : constant Memory_Address :=
                        Memory_Address (Parse_Hex
                           (Packet (Packet'First + 1 .. Comma - 1)));
                     Len  : constant Natural :=
                        Natural (Parse_Hex (Packet (Comma + 1 .. Packet'Last)));
                     Resp : String (1 .. Len * 2 + 8);
                     Pos  : Natural := 1;
                  begin
                     for I in 0 .. Len - 1 loop
                        declare
                           B : constant Byte :=
                              Memory.Read_Byte (Mem,
                                 Addr + Memory_Address (I));
                        begin
                           Resp (Pos .. Pos + 1) := To_Hex (Unsigned_8 (B));
                           Pos := Pos + 2;
                        end;
                     end loop;
                     Send_Packet (Server, Resp (1 .. Pos - 1));
                  end;
               else
                  Send_Packet (Server, "E01");
               end if;
            end;

         --  ---- Memory write ----
         when 'M' =>
            declare
               Comma : constant Natural :=
                  Ada.Strings.Fixed.Index (Packet, ",");
               Colon : constant Natural :=
                  Ada.Strings.Fixed.Index (Packet, ":");
            begin
               if Comma > 0 and Colon > 0 then
                  declare
                     Addr : constant Memory_Address :=
                        Memory_Address (Parse_Hex
                           (Packet (Packet'First + 1 .. Comma - 1)));
                     Data : constant String :=
                        Packet (Colon + 1 .. Packet'Last);
                     Bytes : constant Natural := Data'Length / 2;
                  begin
                     for I in 0 .. Bytes - 1 loop
                        declare
                           Pos : constant Natural := Data'First + I * 2;
                           Val : constant Byte :=
                              Byte (Parse_Hex (Data (Pos .. Pos + 1)));
                        begin
                           Memory.Write_Byte (Mem,
                              Addr + Memory_Address (I),
                              Val);
                        end;
                     end loop;
                     Send_Packet (Server, "OK");
                  end;
               else
                  Send_Packet (Server, "E01");
               end if;
            end;

         --  ---- Continue ----
         when 'c' =>
            Should_Run := True;

         --  ---- Single step ----
         when 's' =>
            Should_Step := True;

         --  ---- vCont / vMustReplyEmpty ----
         when 'v' =>
            if Packet'Length >= 6 and then
               Packet (Packet'First .. Packet'First + 5) = "vCont?"
            then
               Send_Packet (Server, "vCont;c;s;C;S");
            elsif Packet'Length >= 5 and then
               Packet (Packet'First .. Packet'First + 4) = "vCont"
            then
               declare
                  Rest : constant String :=
                     Packet (Packet'First + 5 .. Packet'Last);
               begin
                  if Rest'Length >= 2 and then Rest (Rest'First + 1) = 'c' then
                     Should_Run := True;
                  elsif Rest'Length >= 2 and then Rest (Rest'First + 1) = 's' then
                     Should_Step := True;
                  else
                     Send_Packet (Server, "");
                  end if;
               end;
            elsif Packet'Length >= 15 and then
               Packet (Packet'First .. Packet'First + 14) = "vMustReplyEmpty"
            then
               Send_Packet (Server, "");
            else
               Send_Packet (Server, "");
            end if;

         when 'q' =>
            Handle_Query (Server, Packet, Target_XML);

         when 'Q' =>
            if Packet'Length >= 11 and then
               Packet (Packet'First .. Packet'First + 10) = "QStartNoAck"
            then
               Server.No_Ack_Mode := True;
               Send_Packet (Server, "OK");
            else
               Send_Packet (Server, "");
            end if;

         when 'H' =>
            Send_Packet (Server, "OK");

         when 'T' =>
            Send_Packet (Server, "OK");

         when 'Z' =>
            Handle_Z_Packet (Server, Packet, Insert => True);

         when 'z' =>
            Handle_Z_Packet (Server, Packet, Insert => False);

         when 'k' =>
            Server.Connected := False;

         when 'D' =>
            Send_Packet (Server, "OK");
            Server.Connected := False;

         when others =>
            Send_Packet (Server, "");
      end case;
   end Process_Commands;

   -----------------------
   -- Process_Commands (RV64) --
   -----------------------

   procedure Process_Commands (Server      : in out GDB_Server;
                               CPU         : in out RISCV.CPU64.CPU64_State;
                               Mem         : in out RISCV.Memory.Memory_Unit;
                               Should_Run  : out Boolean;
                               Should_Step : out Boolean) is
      Packet : constant String := Receive_Packet (Server);
   begin
      Should_Run  := False;
      Should_Step := False;

      if Packet'Length = 0 then
         return;
      end if;

      if Packet = "!interrupt" then
         Send_Stop_Reply (Server, CPU, 2);   -- SIGINT
         return;
      end if;

      case Packet (Packet'First) is

         when '?' =>
            Send_Stop_Reply (Server, CPU, 5);   -- SIGTRAP

         --  ---- Register read (all) - 33 * 16 hex chars ----
         when 'g' =>
            --  x0-x31, pc, f0-f31, then fflags/frm/fcsr. The target
            --  description advertises the FPU feature, so the whole block
            --  has to be here: RV64 programs are built lp64d and GDB
            --  refuses a description whose flen does not match the ELF.
            declare
               Response : String (1 .. 33 * 16 + 32 * 16 + 3 * 8);
               Pos : Natural := 1;
               FCSR_Val : constant Word := FPU.Read_FCSR (CPU.FP);
            begin
               for I in 0 .. 31 loop
                  Response (Pos .. Pos + 15) :=
                     To_Hex_DWord (CPU.Registers (Register_Index (I)));
                  Pos := Pos + 16;
               end loop;
               Response (Pos .. Pos + 15) :=
                  To_Hex_DWord (Double_Word (CPU.PC));
               Pos := Pos + 16;
               for I in 0 .. 31 loop
                  Response (Pos .. Pos + 15) :=
                     To_Hex_DWord (Double_Word
                        (FPU.Read_Double (CPU.FP, Register_Index (I))));
                  Pos := Pos + 16;
               end loop;
               --  fflags = fcsr[4:0], frm = fcsr[7:5]
               Response (Pos .. Pos + 7) :=
                  To_Hex_Word (FCSR_Val and 16#1F#);
               Pos := Pos + 8;
               Response (Pos .. Pos + 7) :=
                  To_Hex_Word (Shift_Right (FCSR_Val, 5) and 7);
               Pos := Pos + 8;
               Response (Pos .. Pos + 7) := To_Hex_Word (FCSR_Val);
               Send_Packet (Server, Response);
            end;

         --  ---- Register write (all) ----
         when 'G' =>
            declare
               Data : constant String :=
                  Packet (Packet'First + 1 .. Packet'Last);
            begin
               if Data'Length >= 32 * 16 then
                  for I in 0 .. 31 loop
                     declare
                        Pos : constant Natural := Data'First + I * 16;
                        Val : constant Double_Word :=
                           Parse_Hex_DW (Data (Pos .. Pos + 15));
                     begin
                        CPU.Registers (Register_Index (I)) := Val;
                     end;
                  end loop;
                  if Data'Length >= 33 * 16 then
                     declare
                        Pos : constant Natural := Data'First + 32 * 16;
                     begin
                        CPU.PC := Memory_Address_64
                           (Parse_Hex_DW (Data (Pos .. Pos + 15)));
                     end;
                  end if;
               end if;
               Send_Packet (Server, "OK");
            end;

         --  ---- Single register read - 16 hex chars ----
         when 'p' =>
            declare
               Reg : constant Natural :=
                  Natural (Parse_Hex (Packet (Packet'First + 1 .. Packet'Last)));
            begin
               if Reg <= 31 then
                  Send_Packet (Server,
                     To_Hex_DWord (CPU.Registers (Register_Index (Reg))));
               elsif Reg = 32 then
                  Send_Packet (Server,
                     To_Hex_DWord (Double_Word (CPU.PC)));
               elsif Reg in 33 .. 64 then
                  Send_Packet (Server,
                     To_Hex_DWord (Double_Word
                        (FPU.Read_Double (CPU.FP,
                                          Register_Index (Reg - 33)))));
               elsif Reg = 65 then
                  Send_Packet (Server,
                     To_Hex_Word (FPU.Read_FCSR (CPU.FP) and 16#1F#));
               elsif Reg = 66 then
                  Send_Packet (Server,
                     To_Hex_Word
                       (Shift_Right (FPU.Read_FCSR (CPU.FP), 5) and 7));
               elsif Reg = 67 then
                  Send_Packet (Server, To_Hex_Word (FPU.Read_FCSR (CPU.FP)));
               else
                  Send_Packet (Server, "xxxxxxxxxxxxxxxx");
               end if;
            end;

         --  ---- Single register write ----
         when 'P' =>
            declare
               Eq : constant Natural :=
                  Ada.Strings.Fixed.Index (Packet, "=");
            begin
               if Eq > 0 then
                  declare
                     Reg : constant Natural :=
                        Natural (Parse_Hex
                           (Packet (Packet'First + 1 .. Eq - 1)));
                     Val : constant Double_Word :=
                        Parse_Hex_DW (Packet (Eq + 1 .. Packet'Last));
                  begin
                     if Reg <= 31 then
                        CPU.Registers (Register_Index (Reg)) := Val;
                     elsif Reg = 32 then
                        CPU.PC := Memory_Address_64 (Val);
                     elsif Reg in 33 .. 64 then
                        FPU.Write_Double (CPU.FP, Register_Index (Reg - 33),
                                          FPU.FP_Register (Val));
                     elsif Reg = 67 then
                        FPU.Write_FCSR
                          (CPU.FP, Word (Val and 16#FFFF_FFFF#));
                     end if;
                  end;
               end if;
               Send_Packet (Server, "OK");
            end;

         --  ---- Memory read ----
         when 'm' =>
            declare
               Comma : constant Natural :=
                  Ada.Strings.Fixed.Index (Packet, ",");
            begin
               if Comma > 0 then
                  declare
                     Addr : constant Memory_Address :=
                        Memory_Address (Parse_Hex_DW
                           (Packet (Packet'First + 1 .. Comma - 1)));
                     Len  : constant Natural :=
                        Natural (Parse_Hex (Packet (Comma + 1 .. Packet'Last)));
                     Resp : String (1 .. Len * 2 + 8);
                     Pos  : Natural := 1;
                  begin
                     for I in 0 .. Len - 1 loop
                        declare
                           B : constant Byte :=
                              Memory.Read_Byte (Mem,
                                 Addr + Memory_Address (I));
                        begin
                           Resp (Pos .. Pos + 1) := To_Hex (Unsigned_8 (B));
                           Pos := Pos + 2;
                        end;
                     end loop;
                     Send_Packet (Server, Resp (1 .. Pos - 1));
                  end;
               else
                  Send_Packet (Server, "E01");
               end if;
            end;

         --  ---- Memory write ----
         when 'M' =>
            declare
               Comma : constant Natural :=
                  Ada.Strings.Fixed.Index (Packet, ",");
               Colon : constant Natural :=
                  Ada.Strings.Fixed.Index (Packet, ":");
            begin
               if Comma > 0 and Colon > 0 then
                  declare
                     Addr : constant Memory_Address :=
                        Memory_Address (Parse_Hex_DW
                           (Packet (Packet'First + 1 .. Comma - 1)));
                     Data : constant String :=
                        Packet (Colon + 1 .. Packet'Last);
                     Bytes : constant Natural := Data'Length / 2;
                  begin
                     for I in 0 .. Bytes - 1 loop
                        declare
                           Pos : constant Natural := Data'First + I * 2;
                           Val : constant Byte :=
                              Byte (Parse_Hex (Data (Pos .. Pos + 1)));
                        begin
                           Memory.Write_Byte (Mem,
                              Addr + Memory_Address (I),
                              Val);
                        end;
                     end loop;
                     Send_Packet (Server, "OK");
                  end;
               else
                  Send_Packet (Server, "E01");
               end if;
            end;

         --  ---- Continue ----
         when 'c' =>
            Should_Run := True;

         --  ---- Single step ----
         when 's' =>
            Should_Step := True;

         --  ---- vCont ----
         when 'v' =>
            if Packet'Length >= 6 and then
               Packet (Packet'First .. Packet'First + 5) = "vCont?"
            then
               Send_Packet (Server, "vCont;c;s;C;S");
            elsif Packet'Length >= 5 and then
               Packet (Packet'First .. Packet'First + 4) = "vCont"
            then
               declare
                  Rest : constant String :=
                     Packet (Packet'First + 5 .. Packet'Last);
               begin
                  if Rest'Length >= 2 and then Rest (Rest'First + 1) = 'c' then
                     Should_Run := True;
                  elsif Rest'Length >= 2 and then Rest (Rest'First + 1) = 's' then
                     Should_Step := True;
                  else
                     Send_Packet (Server, "");
                  end if;
               end;
            elsif Packet'Length >= 15 and then
               Packet (Packet'First .. Packet'First + 14) = "vMustReplyEmpty"
            then
               Send_Packet (Server, "");
            else
               Send_Packet (Server, "");
            end if;

         when 'q' =>
            Handle_Query (Server, Packet, Target_XML_64);

         when 'Q' =>
            if Packet'Length >= 11 and then
               Packet (Packet'First .. Packet'First + 10) = "QStartNoAck"
            then
               Server.No_Ack_Mode := True;
               Send_Packet (Server, "OK");
            else
               Send_Packet (Server, "");
            end if;

         when 'H' =>
            Send_Packet (Server, "OK");

         when 'T' =>
            Send_Packet (Server, "OK");

         when 'Z' =>
            Handle_Z_Packet (Server, Packet, Insert => True);

         when 'z' =>
            Handle_Z_Packet (Server, Packet, Insert => False);

         when 'k' =>
            Server.Connected := False;

         when 'D' =>
            Send_Packet (Server, "OK");
            Server.Connected := False;

         when others =>
            Send_Packet (Server, "");
      end case;
   end Process_Commands;

   ---------------------
   -- Send_Stop_Reply (RV32) --
   ---------------------

   procedure Send_Stop_Reply (Server : in out GDB_Server;
                              CPU    : RISCV.CPU.CPU_State;
                              Signal : Natural := 5) is
      Sig_Hex : constant String := To_Hex (Unsigned_8 (Signal));
   begin
      Send_Packet (Server,
         "T" & Sig_Hex &
         "02:" & To_Hex_Word (CPU.Registers (Register_Index (2))) & ";" &
         "20:" & To_Hex_Word (CPU.PC) & ";");
   end Send_Stop_Reply;

   ---------------------
   -- Send_Stop_Reply (RV64) --
   ---------------------

   procedure Send_Stop_Reply (Server : in out GDB_Server;
                              CPU    : RISCV.CPU64.CPU64_State;
                              Signal : Natural := 5) is
      Sig_Hex : constant String := To_Hex (Unsigned_8 (Signal));
   begin
      Send_Packet (Server,
         "T" & Sig_Hex &
         "02:" & To_Hex_DWord (CPU.Registers (Register_Index (2))) & ";" &
         "20:" & To_Hex_DWord (Double_Word (CPU.PC)) & ";");
   end Send_Stop_Reply;

   ----------------------------
   -- Watchpoint_Stop_Prefix --
   ----------------------------

   function Watchpoint_Stop_Prefix (Server   : GDB_Server;
                                    Addr     : Double_Word;
                                    Is_Write : Boolean) return String is
      Addr_Str : constant String := To_Hex_Word (Word (Addr and 16#FFFF_FFFF#));
   begin
      for I in 1 .. Server.Num_Watchpoints loop
         if Server.Watchpoints (I).Valid and then
            Server.Watchpoints (I).Addr = Addr
         then
            case Server.Watchpoints (I).Kind is
               when Watch_Write =>
                  if Is_Write then
                     return "watch:" & Addr_Str & ";";
                  end if;
               when Watch_Read =>
                  if not Is_Write then
                     return "rwatch:" & Addr_Str & ";";
                  end if;
               when Watch_Access =>
                  return "awatch:" & Addr_Str & ";";
            end case;
         end if;
      end loop;
      return "";
   end Watchpoint_Stop_Prefix;

   ---------------------------
   -- Send_Watchpoint_Stop (RV32) --
   ---------------------------

   procedure Send_Watchpoint_Stop (Server     : in out GDB_Server;
                                   CPU        : RISCV.CPU.CPU_State;
                                   Watch_Addr : Double_Word;
                                   Is_Write   : Boolean;
                                   Signal     : Natural := 5) is
      Sig_Hex      : constant String := To_Hex (Unsigned_8 (Signal));
      Watch_Prefix : constant String :=
         Watchpoint_Stop_Prefix (Server, Watch_Addr, Is_Write);
   begin
      Send_Packet (Server,
         "T" & Sig_Hex &
         Watch_Prefix &
         "02:" & To_Hex_Word (CPU.Registers (Register_Index (2))) & ";" &
         "20:" & To_Hex_Word (CPU.PC) & ";");
   end Send_Watchpoint_Stop;

   ---------------------------
   -- Send_Watchpoint_Stop (RV64) --
   ---------------------------

   procedure Send_Watchpoint_Stop (Server     : in out GDB_Server;
                                   CPU        : RISCV.CPU64.CPU64_State;
                                   Watch_Addr : Double_Word;
                                   Is_Write   : Boolean;
                                   Signal     : Natural := 5) is
      Sig_Hex      : constant String := To_Hex (Unsigned_8 (Signal));
      Watch_Prefix : constant String :=
         Watchpoint_Stop_Prefix (Server, Watch_Addr, Is_Write);
   begin
      Send_Packet (Server,
         "T" & Sig_Hex &
         Watch_Prefix &
         "02:" & To_Hex_DWord (CPU.Registers (Register_Index (2))) & ";" &
         "20:" & To_Hex_DWord (Double_Word (CPU.PC)) & ";");
   end Send_Watchpoint_Stop;

   ------------
   -- To_Hex --
   ------------

   function To_Hex (V : Unsigned_8) return String is
      Hex_Digits : constant String := "0123456789abcdef";
   begin
      return (1 => Hex_Digits (Natural (Shift_Right (V, 4)) + 1),
              2 => Hex_Digits (Natural (V and 16#0F#) + 1));
   end To_Hex;

   ------------------
   -- To_Hex_Word --
   ------------------

   function To_Hex_Word (V : Word) return String is
      Result : String (1 .. 8);
      Val : Word := V;
   begin
      --  Little-endian byte order as required by the RSP wire format
      for I in 0 .. 3 loop
         declare
            B : constant Unsigned_8 := Unsigned_8 (Val and 16#FF#);
         begin
            Result (I * 2 + 1 .. I * 2 + 2) := To_Hex (B);
            Val := Shift_Right (Val, 8);
         end;
      end loop;
      return Result;
   end To_Hex_Word;

   -------------------
   -- To_Hex_DWord --
   -------------------

   function To_Hex_DWord (V : Double_Word) return String is
      Result : String (1 .. 16);
      Val : Double_Word := V;
   begin
      --  Little-endian byte order (8 bytes)
      for I in 0 .. 7 loop
         declare
            B : constant Unsigned_8 := Unsigned_8 (Val and 16#FF#);
         begin
            Result (I * 2 + 1 .. I * 2 + 2) := To_Hex (B);
            Val := Shift_Right (Val, 8);
         end;
      end loop;
      return Result;
   end To_Hex_DWord;

   ---------------
   -- Parse_Hex --
   ---------------

   function Parse_Hex (S : String) return Word is
      Result : Word := 0;
   begin
      for I in S'Range loop
         Result := Shift_Left (Result, 4);
         if S (I) in '0' .. '9' then
            Result := Result + Word (Character'Pos (S (I)) - Character'Pos ('0'));
         elsif S (I) in 'a' .. 'f' then
            Result := Result + Word (Character'Pos (S (I)) - Character'Pos ('a') + 10);
         elsif S (I) in 'A' .. 'F' then
            Result := Result + Word (Character'Pos (S (I)) - Character'Pos ('A') + 10);
         end if;
      end loop;
      return Result;
   end Parse_Hex;

   ------------------
   -- Parse_Hex_DW --
   ------------------

   function Parse_Hex_DW (S : String) return Double_Word is
      Result : Double_Word := 0;
   begin
      for I in S'Range loop
         Result := Shift_Left (Result, 4);
         if S (I) in '0' .. '9' then
            Result := Result +
               Double_Word (Character'Pos (S (I)) - Character'Pos ('0'));
         elsif S (I) in 'a' .. 'f' then
            Result := Result +
               Double_Word (Character'Pos (S (I)) - Character'Pos ('a') + 10);
         elsif S (I) in 'A' .. 'F' then
            Result := Result +
               Double_Word (Character'Pos (S (I)) - Character'Pos ('A') + 10);
         end if;
      end loop;
      return Result;
   end Parse_Hex_DW;

   ------------------------
   -- Calculate_Checksum --
   ------------------------

   function Calculate_Checksum (Data : String) return Unsigned_8 is
      Sum : Unsigned_8 := 0;
   begin
      for I in Data'Range loop
         Sum := Sum + Unsigned_8 (Character'Pos (Data (I)));
      end loop;
      return Sum;
   end Calculate_Checksum;

end RISCV.GDB;
