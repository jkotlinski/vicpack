(*
Copyright (c) 2007, Johan Kotlinski

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*)

open Images;;
open OImages;;
open Printf;;
open Graphics;;

module type INT = sig
    type t = int
    val compare : t -> t -> int
end;;
module Int : INT = struct
    type t = int
    let compare i j = j - i
end;;
module IntSet = Set.Make(Int);;

type gfxmode = 
    | Multicolor
    | Hires
    | Asslace
    | Fli;;

let rec c64charcompare c1 c2 =
    if c1 = [] then
        0
    else
        let val1 = (List.hd c1) 
        and val2 = (List.hd c2) in
        if val1 = val2 then
            c64charcompare (List.tl c1) (List.tl c2)
        else
            compare val1 val2
;;

let equals c1 c2 =
    (c64charcompare c1 c2) = 0

let get_colors ch =
    let colors = ref IntSet.empty in
    let add_color_to_set c =
        if c != 0xff then
            colors := IntSet.add c !colors
    in
    List.iter add_color_to_set ch;
    !colors
;;

let write_char channel c = fprintf channel "%c" c;;
let write_int channel c = fprintf channel "%c" (char_of_int c);;

let rec downsample lst =
    match lst with
    [] -> lst
    | head :: tail -> head :: (downsample (List.tl tail))
;;

let mc_fli_write hires_ch bg oc_char oc_c oc_v =
    let ch = downsample hires_ch in
    let colors = ref (get_colors ch) in

    let find_cram_color =
        let possible_colors = BitSet.create 16 in
        for i = 0 to 15 do
            BitSet.set possible_colors i
        done;

        let x = ref 0
        and ch_colors = BitSet.create 16
        in
        let handle color =
            if bg != color then
                BitSet.set ch_colors color;

            incr x;
            if !x = 4 then
                begin
                    x := 0;
                    if BitSet.count ch_colors = 3 then
                        BitSet.intersect possible_colors ch_colors;
                    BitSet.differentiate ch_colors ch_colors; (* clean *)
                end
        in
        List.iter handle ch;

        let retval = ref (-1) in
        let all_were_set = ref true in
        for i = 0 to 15 do
            if BitSet.is_set possible_colors i then
                retval := i
            else
                all_were_set := false
        done;
        if !all_were_set then retval := bg;
        if !retval = -1 then failwith "No possible char color found!";
        !retval
    in

    let cram_val = find_cram_color in
    write_int oc_c cram_val;

    colors := IntSet.remove bg !colors;
    colors := IntSet.remove cram_val !colors;

    let find_vram_colors =
        let found_colors = ref [] 
        and vram1 = ref (-1) 
        and vram2 = ref (-1)
        and x = ref 0 
        in
        let handle color =
            if color != bg && 
                color != cram_val && 
                color != !vram1 && 
                color != !vram2 
            then
                begin
                    if !vram1 = -1 then
                        vram1 := color
                    else
                        begin
                            assert (!vram2 = -1);
                            vram2 := color
                        end;
                end;
            incr x;
            if !x = 4 then
                begin
                    if !vram1 = (-1) then vram1 := 0;
                    if !vram2 = (-1) then vram2 := 0;
                    found_colors := !found_colors @ [(!vram1, !vram2)];
                    vram1 := (-1);
                    vram2 := (-1);
                    x := 0
                end
        in
        List.iter handle ch;
        !found_colors
    in

    let vram_colors = find_vram_colors 
    and bitmapval = ref 0
    and bytecount = ref 0
    and row = ref 0
    in
    let write_bitmap pixel =
        bitmapval := !bitmapval lsl 2;
        let (vram1, vram2) = List.nth vram_colors !row in

        (* multicolor bitmap:
            00 = bg color
            01 = upper nibble of video matrix
            10 = lower nibble of video matrix
            11 = color ram nibble $d800- *)
        bitmapval := !bitmapval +
            if pixel = bg then 0
            else if pixel = vram1 then 1
            else if pixel = vram2 then 2
            else if pixel = cram_val then 3
            else failwith "Bad color";

        incr bytecount;
        if !bytecount = 4 then
            begin
                write_int oc_char !bitmapval;
                bytecount := 0;
                bitmapval := 0;
                incr row
            end
    in
    List.iter write_bitmap ch;
    vram_colors
;;

let mc_write charwidth charheight hires_ch bg escos_bg1 escos_bg2 oc_char (oc_c:out_channel) (oc_v:out_channel) =
    let escos = (charwidth = 24) in
    assert (charwidth * charheight = (List.length hires_ch));
    let ch = downsample hires_ch in
    let colors = ref (get_colors ch) in
    assert ((IntSet.cardinal !colors) < 5);
    colors := IntSet.remove bg !colors;
    if escos then
        begin
            colors := IntSet.remove escos_bg1 !colors;
            colors := IntSet.remove escos_bg2 !colors;
        end;
    let colorList = (IntSet.elements !colors)
    and colorMap = (Array.make 16 0) in
    Array.set colorMap bg 0;
    if escos then
        begin
            Array.set colorMap escos_bg1 1;
            Array.set colorMap escos_bg2 2
        end;

    if not escos then
        begin
            (* multicolor bitmap:
                00 = bg color
                01 = upper nibble of video matrix
                10 = lower nibble of video matrix
                11 = color ram nibble $d800- *)
            let cram_val = ref 0xff
            and vram_val = ref 0
            and colorCount = (List.length colorList) in
            if colorCount = 1 then
                begin
                    let c1 = List.hd colorList in
                    Array.set colorMap c1 1;
                    vram_val := c1 lsl 4
                end
            else if colorCount = 2 then
                begin
                    let c1 = List.hd colorList
                    and c2 = List.nth colorList 1 in
                    Array.set colorMap c1 1;
                    Array.set colorMap c2 2;
                    vram_val := (c1 lsl 4) + c2
                end
            else if colorCount = 3 then
                begin
                    let c1 = List.hd colorList
                    and c2 = List.nth colorList 1 in
                    cram_val := List.nth colorList 2;
                    Array.set colorMap c1 1;
                    Array.set colorMap c2 2;
                    Array.set colorMap !cram_val 3;
                    vram_val := (c1 lsl 4) + c2;
                end;
			write_int oc_c !cram_val;
			write_int oc_v !vram_val;
        end
    else
        begin
            (* escos
			00 = $d020, $d021
			01 = $d025
			10 = $d026
			11 = sprite color *)
            let cram_val = ref 0
            and colorCount = (List.length colorList) in
            if colorCount = 1 then
                begin
                    cram_val := List.hd colorList;
                    Array.set colorMap !cram_val 3
                end;
			write_int oc_c !cram_val;
        end;

    let pixelCount = ref 0
    and rowValue = ref 0 in

    let write pixel =
        rowValue := !rowValue lsl 2;
        rowValue := !rowValue + (Array.get colorMap pixel);
        incr pixelCount;
		if !pixelCount = 4 then
		begin
			write_int oc_char !rowValue;
            rowValue := 0;
            pixelCount := 0
        end
    in
    List.iter write ch
;;

let hires_write ch oc_char (oc_v:out_channel) charwidth charheight bg =
    assert (charwidth * charheight = (List.length ch));
    let escos = (charwidth = 24 ) in
    let colors = ref (get_colors ch) in
    if (IntSet.cardinal !colors > 2) then
        failwith "Too many colors!";
    let colorList = (IntSet.elements !colors)
    and colorMap = (Array.make 16 0)
    and vram_val = ref 0 in

    if escos then
        let pick color =
            if color != bg then
                vram_val := color
        in
        List.iter pick colorList
    else
        begin
            let colorCount = (List.length colorList) in
            if colorCount = 1 then
                begin
                    vram_val := List.hd colorList;
                    Array.set colorMap !vram_val 0
                end
            else if colorCount = 2 then
                begin
                    let v1 = List.hd colorList in
                    let v2 = List.nth colorList 1 in
                    Array.set colorMap v1 0;
                    Array.set colorMap v2 1;
                    vram_val := (v2 lsl 4) + v1
                end
        end;

    write_int oc_v !vram_val;

    let pixelCount = ref 0 in
    let rowValue = ref 0 in

    let write pixel =
        rowValue := !rowValue lsl 1;
        if pixel != 0xff then
            rowValue := !rowValue + 
                if escos then
                    if pixel != bg then 1 else 0
                else
                    (Array.get colorMap pixel);
        incr pixelCount;
        if !pixelCount = charwidth then
            begin
                if charwidth = 8 then
                    write_int oc_char !rowValue
                else if charwidth = 24 then
                    begin
                        write_int oc_char ((!rowValue lsr 16));
                        write_int oc_char (((!rowValue lsr 8) land 0xff));
                        write_int oc_char ((!rowValue land 0xff))
                    end
                else
                    failwith "Unsupported charwidth";

                rowValue := 0;
                pixelCount := 0
            end
    in
    List.iter write ch
;;

let get_c64_color i =
    let colors = [|
        (rgb 0x00 0x00 0x00);
        (rgb 0xFF 0xFF 0xFF);
        (rgb 0x68 0x37 0x2B);
        (rgb 0x70 0xA4 0xB2);
        (rgb 0x6F 0x3D 0x86);
        (rgb 0x58 0x8D 0x43);
        (rgb 0x35 0x28 0x79);
        (rgb 0xB8 0xC7 0x6F);
        (rgb 0x6F 0x4F 0x25);
        (rgb 0x43 0x39 0x00);
        (rgb 0x9A 0x67 0x59);
        (rgb 0x44 0x44 0x44);
        (rgb 0x6C 0x6C 0x6C);
        (rgb 0x9A 0xD2 0x84);
        (rgb 0x6C 0x5E 0xB5);
        (rgb 0x95 0x95 0x95) 
        |] 
    in
    colors.(i);
;;

let find_closest_color (c:Color.rgb) =
    let calc_error c1 c2 =
        let r_error = c1.r - (c2 land 0xff0000 ) asr 16 in
        let g_error = c1.g - (c2 land 0xff00 ) asr 8 in
        let b_error = c1.b - (c2 land 0xff ) in

        0.299 *. (float r_error) *. (float r_error) +.
        0.587 *. (float g_error) *. (float g_error) +.
        0.114 *. (float b_error) *. (float b_error)
    in

    let closest_color = ref 0 in
    let smallest_error = ref (calc_error c (get_c64_color 0)) in
    for i = 1 to 15 do
        let error = calc_error c (get_c64_color i) in
        if error < !smallest_error then
            begin
                closest_color := i;
                smallest_error := error
            end
    done;
    assert ( !closest_color >= 0 && !closest_color < 16 );
    !closest_color
;;

let prepare_for_asslace bmp =
    for y = 0 to bmp#height - 1 do
        let swap x1 x2 =
            let tmp = bmp#get x1 y in
            bmp#set x1 y (bmp#get x2 y);
            bmp#set x2 y tmp
        in
        for x = 0 to (bmp#width / 4) - 1 do
            let x = x * 4 in
            swap (x+2) (x+3);
            if y mod 2 = 1 then
                begin
                    swap x (x+1);
                    swap (x+2) (x+3);
                end
        done;
    done;
    bmp
;;

let convert_to_64_colors bmp =
    let width = bmp#width in
    let height = bmp#height in

    for x = 0 to width - 1 do
        for y = 0 to height - 1 do
            let rgbColor = bmp#get x y in
            let c = (find_closest_color rgbColor) in 
            rgbColor.r <- 0;
            rgbColor.g <- 0;
            rgbColor.b <- c;
            bmp#set x y rgbColor;
        done
    done
;;

let process_row bmp startx starty charwidth charheight =
    let row_colors = ref [] in
    for dx = 0 to charwidth - 1 do
        let x = startx + dx in
        let rgbColor = bmp#get x starty in
        let c = rgbColor.b in 
        row_colors := !row_colors @ [c];
    done;
    !row_colors;
;;

let process_char (bmp:rgb24) startx starty charwidth charheight =
    let ch = ref [] in
    for dy = 0 to charheight - 1 do
        let y = starty + dy in
        let row = process_row bmp startx y charwidth charheight in
        ch := !ch @ row
    done;
    !ch
;;

let get_charlist (bmp:rgb24) charwidth charheight =
    let charlist = ref [] in
    let width = bmp#width in
    let height = bmp#height in

    if height mod charheight != 0 then
        failwith ("Height is not a multiple of " ^ string_of_int charheight);
    if width mod charwidth != 0 then
        failwith ("Width is not a multiple of " ^ string_of_int charwidth);

    for y = 0 to height/charheight-1 do
        for x = 0 to width/charwidth-1 do
            let ch = [process_char bmp (x*charwidth) (y*charheight) charwidth charheight] in
            charlist := !charlist @ ch;
        done
    done;
    !charlist
;;

let dump_charmap charmap infilename =
    let outfilename = infilename ^ "_map.bin" in
    let oc = open_out_bin outfilename in
    let write ch = 
        begin
            assert (ch < 256);
            write_int oc ch;
        end
    in
    List.iter write charmap;
    close_out oc
;;

let dump_hires_chars charwidth charheight bg charlist infilename =
    let outfilename_chars = infilename ^ ".bin" in
    let oc_chars = open_out_bin outfilename_chars in

    let outfilename_v = infilename ^ 
        if charwidth = 24 then "-colors.bin" else "-v.bin" 
    in
    let oc_v = open_out_bin outfilename_v in

    let write ch =
        hires_write ch oc_chars oc_v charwidth charheight bg
    in
    List.iter write charlist;
    close_out oc_chars;
    close_out oc_v
;;

let dump_mc_chars escos_bg1 escos_bg2 mode charwidth charheight bg charlist infilename =
    let outfilename_chars = infilename ^ ".bin" in
    let oc_chars = open_out_bin outfilename_chars in

    let outfilename_c = infilename ^ "-c.bin" in
    let oc_c = open_out_bin outfilename_c in

    let outfilename_v = infilename ^ "-v.bin" in
    let oc_v = open_out_bin outfilename_v in

    let vram_colors = ref [] in
    let write ch =
        if mode = Multicolor || mode = Asslace then
            mc_write charwidth charheight ch bg escos_bg1 escos_bg2 oc_chars oc_c oc_v
        else
            (* Fli *)
            vram_colors := !vram_colors @ mc_fli_write ch bg oc_chars oc_c oc_v;
    in
    List.iter write charlist;

    if mode = Fli then
        begin
            (* write vram colors *)
            for i = 0 to 7 do
                let wrote = ref 0
                and j = ref (i) in
                while !j < List.length !vram_colors do
                    let (vram1, vram2) = List.nth !vram_colors !j in
                    write_int oc_v ((vram1 lsl 4) + vram2);
                    j := !j + 8;
                    incr wrote;
                done;
                for j = !wrote to 0x3ff do
                    write_int oc_v 0;
                done
            done
        end;

    close_out oc_chars;
    close_out oc_c;
    close_out oc_v
;;

let strip_duplicate_chars charlist =
    let sorted_charlist = ref (List.sort c64charcompare charlist) in
    let unique_list = ref [] in

    while !sorted_charlist != [] do
        let head = List.hd !sorted_charlist in
        sorted_charlist := (List.tl !sorted_charlist);

        if !sorted_charlist = [] then
            unique_list := head :: !unique_list
        else
            let head2 = (List.hd !sorted_charlist) in
            if not (equals head head2) then
                unique_list := head :: !unique_list;
    done;
    unique_list
;;

let find_char_in_array ch unique_chars =
    let found_index = ref 0 in
    for i = 0 to (Array.length unique_chars) - 1 do
        if equals ch (Array.get unique_chars i) then
            found_index := i;
    done;
    !found_index
;;

let rec calc_charmap charlist unique_chars =
    let head = List.hd charlist in
    let index = find_char_in_array head unique_chars in
    let retval = ref [index] in

    let tail = List.tl charlist in
    if tail != [] then
        retval := !retval @ (calc_charmap tail unique_chars);
    !retval
;;

let find_escos_mc_bg_colors charlist =
    let bg_colors = ref IntSet.empty in
    for i = 0 to 15 do
        bg_colors := IntSet.add i !bg_colors
    done;
    let examine_char c64char =
        let colors = (get_colors c64char) in
        assert ( IntSet.cardinal colors < 5 );
        if IntSet.cardinal colors = 4 then
            for i = 0 to 15 do
                if not (IntSet.mem i colors) then
                    bg_colors := IntSet.remove i !bg_colors
            done
    in
    List.iter examine_char charlist;
    !bg_colors
;;

let find_escos_bg_colors charlist =
    let bg_colors = ref IntSet.empty in
    for i = 0 to 15 do
        bg_colors := IntSet.add i !bg_colors
    done;
    let examine_char c64char =
        let colors = (get_colors c64char) in
        if IntSet.cardinal colors = 2 then
            for i = 0 to 15 do
                if not (IntSet.mem i colors) then
                    bg_colors := IntSet.remove i !bg_colors
            done
    in
    List.iter examine_char charlist;
    !bg_colors
;;

let find_bg_colors charwidth charlist mode debug =
    if debug then printf "Find bg colors...\n";
    let bg_colors = ref IntSet.empty in
    for i = 0 to 15 do
        bg_colors := IntSet.add i !bg_colors
    done;
    if mode != Fli then
        begin
            let examine_char c64char =
                let colors = get_colors c64char in
                let colorCount = IntSet.cardinal colors in
                if 4 = IntSet.cardinal colors then
                    begin
                        bg_colors := IntSet.inter !bg_colors colors;
                        if (IntSet.cardinal !bg_colors = 0) then
                            failwith "Can't find background color!"
                    end;
                if (colorCount > 4) then
                    failwith "Too many colors in a single char!";
            in
            List.iter examine_char charlist
        end
    else
        begin
            (* fli... examine row by row *)
            let row = ref [] in
            let examine_char c64char =
                let examine_pixel pixel =
                    row := pixel :: !row;
                    if (List.length !row) = charwidth then
                        begin
                            let colors = get_colors !row in
                            if 4 = IntSet.cardinal colors then
                                bg_colors := IntSet.inter !bg_colors colors;
                            row := []
                        end
                in
                List.iter examine_pixel c64char
            in
            List.iter examine_char charlist;
        end;
        
    !bg_colors
;;

let do_generate_prg path file mode interlace bg bg2 border use_sprites =
    let src = 
        if mode = Hires then 
            if use_sprites then
                Asm6510.hires_sprite_viewer
            else
                Asm6510.hires_viewer
        else
            if mode = Fli then
                Asm6510.fli_viewer
            else
                (* mode = Multicolor or Asslace *)
                if interlace then
                    if mode = Asslace then
                        Asm6510.asslace_viewer
                    else
                        Asm6510.mci_viewer
                else
                    Asm6510.multicolor_viewer
    in
    let asmfilename = file ^ ".a" in
    let oc = open_out asmfilename in

    let str = Str.global_replace (Str.regexp "__FILE__") file src in
    let str = Str.global_replace (Str.regexp "__BORDERCOLOR__") (string_of_int border) str in
    let str = Str.global_replace (Str.regexp "__BGCOLOR__") (string_of_int bg) str in
    let str = Str.global_replace (Str.regexp "__BGCOLOR1__") (string_of_int bg) str in
    let str = Str.global_replace (Str.regexp "__BGCOLOR2__") (string_of_int bg2) str in

    fprintf oc "%s"  str;
    close_out oc;
    let acme = 
        if Sys.os_type = "Cygwin" then "./acme.exe" else "acme" in
    let cmd = path ^ acme ^ " " ^ asmfilename in
    printf "%s\n"  cmd;
    let status = Unix.system cmd in 
    match status with
    Unix.WEXITED 0 -> ()
    | Unix.WEXITED n ->
        let msg = Printf.sprintf "Command %s exited with code %d" cmd n in
        failwith msg
    | Unix.WSTOPPED n ->
        let msg = Printf.sprintf "Command %s stopped by signal %d" cmd n in
        failwith msg
    | Unix.WSIGNALED n ->
        let msg = Printf.sprintf "Command %s killed by signal %d" cmd n
        in failwith msg
;;

let process_charlist mode bg escos unique_chars charwidth charheight debug charlist file =
    let bg_sprite_1 = ref 0
    and bg_sprite_2 = ref 1 
    and bg = ref (bg) in
    if (mode = Multicolor || mode = Fli || mode = Asslace) && (!bg = 0xff) then
        if not escos then
            begin
                let bgcolors = find_bg_colors charwidth charlist mode debug in
                let bgcolorlist = IntSet.elements bgcolors in
                if (List.length bgcolorlist) < 1 then
                    failwith "Too few possible bgcolors found!\n";
                    bg := List.hd bgcolorlist;
                    printf "bgcolor: %d\n" !bg;
                    assert (IntSet.mem !bg bgcolors);
            end
        else
            begin
                (* escos multicolor *)
                let bgcolors = find_escos_mc_bg_colors charlist in
                let bgcolorlist = IntSet.elements bgcolors in
                if (List.length bgcolorlist) < 3 then
                    failwith "Too few possible bgcolors found!\n";
                    bg := List.hd bgcolorlist;
                    bg_sprite_1 := List.nth bgcolorlist 1;
                    bg_sprite_2 := List.nth bgcolorlist 2;
                    printf "bgcolor: %d\n" !bg;
                    printf "$d025: %d\n" !bg_sprite_1;
                    printf "$d026: %d\n" !bg_sprite_2;
                    assert (IntSet.mem !bg bgcolors);
            end;

    if mode = Hires && escos = true && (!bg = 0xff) then
        begin
            let bgcolors = find_escos_bg_colors charlist in
            let bgcolorlist = IntSet.elements bgcolors in
            if (List.length bgcolorlist) < 1 then
                failwith "Too few possible bgcolors found!\n";
            bg := List.hd bgcolorlist;
            printf "bgcolor: %d\n" !bg;
            assert (IntSet.mem !bg bgcolors);
        end;

    let dump_chars =
        match mode with
        | Hires -> dump_hires_chars 
        | Multicolor
        | Asslace
        | Fli -> dump_mc_chars !bg_sprite_1 !bg_sprite_2 mode
    in

    if unique_chars then 
        begin
            let unique_list = !(strip_duplicate_chars charlist) in
            if List.length unique_list > 255 then
                failwith "More than 256 unique chars!";
            let charmap = (calc_charmap charlist (Array.of_list unique_list)) in
            dump_chars charwidth charheight !bg unique_list file;
            dump_charmap charmap file;
        end
    else
        dump_chars charwidth charheight !bg charlist file;

    !bg
;;

let merge_mci_cram file =
    let cram_out = open_out_bin (file ^ "-c.bin")
    and cram1_in = open_in_bin (file ^ "1-c.bin")
    and cram2_in = open_in_bin (file ^ "2-c.bin")
    in
    try
        while true do
            let cram1 = input_char cram1_in
            and cram2 = input_char cram2_in
            in
            write_char cram_out 
                (if cram1 = (char_of_int 0xff) then
                    cram2
                else
                    cram1)
        done
    with End_of_file -> ();
    close_out cram_out;
    close_in cram1_in;
    close_in cram1_in;
    Unix.unlink (file ^ "1-c.bin");
    Unix.unlink (file ^ "2-c.bin")
;;

let unique_chars = ref false
and mode = ref Hires
and escos = ref false
and escos_no_ystretch = ref false
and interlace = ref false
and use_sprites = ref false
and custom_char_height = ref 0
and bg = ref 0xff
and border = ref 0
and debug = ref false
and generate_prg = ref false
and files = ref []
and path =
    if Str.string_match (Str.regexp "^.*[\\|/]") Sys.argv.(0) 0 then
        Str.matched_string Sys.argv.(0)
    else
        ""
in
Arg.parse [
    ("-h", Arg.Unit (fun () -> mode := Hires),
    "Convert to hires");
    ("-mc", Arg.Unit (fun () -> mode := Multicolor),
    "Convert to multicolor");
    ("-ass", Arg.Unit (fun () -> mode := Asslace; interlace := true),
    "Convert to Asslace");
    ("-fli", Arg.Unit (fun () -> mode := Fli),
    "Convert to FLI");
    ("-mci", Arg.Unit (fun () -> mode := Multicolor; interlace := true),
    "Convert to MCI");
    ("-e", Arg.Unit (fun () -> escos := true; escos_no_ystretch := true),
    "ESCOS: Convert to sprites (no vertical stretch)");
    ("-e2", Arg.Unit (fun () -> escos := true ),
    "ESCOS: Convert to sprites (2x vertical stretch)");
    ("-s", Arg.Unit (fun () -> use_sprites := true),
    "Use sprite overlays (hires only)");
    ("-u", Arg.Unit (fun () -> unique_chars := true),
    "Unique chars, generate map file");
    ("-y", Arg.Int (fun i -> custom_char_height := i),
    "Custom char height (ESCOS: sprite height)");
    ("-bg", Arg.Int (fun i -> bg := i; assert ( (i > -1) & (i < 16) ) ),
    "Force background color");
    ("-border", Arg.Int (fun i -> border := i; assert ( (i > -1) & (i < 16) ) ),
    "Custom border color");
    ("-d", Arg.Unit (fun () -> debug := true),
    "Debug mode");
    ("-p", Arg.Unit (fun () -> generate_prg := true),
    "Generate .prg file")
] 
(fun s -> files := s :: !files) "Input images";
let files = List.rev !files in
if ((List.length files) = 0) then
    begin
        printf "vicpack v0.07. Copyright (c) 2007, Johan Kotlinski

usage: vicpack [-options] files

-h: hires (default)
-mc: multicolor
-fli: FLI
-mci: MCI
-e: ESCOS - convert to sprites (no vertical stretch)
-e2: ESCOS - convert to sprites (2x vertical stretch)
-bg n: force background color n (for use with multicolor)
-border n: custom border color n
-s: use sprite overlays (hires only)
-u: unique chars, generate map file
-y n: custom char/sprite height
-d: debug mode
-p: generate .prg file (requires acme)

For best results, use Pepto's palette: http://www.pepto.de/projects/colorvic/
"
    end;
    List.iter (fun file ->
        let file =
            if Sys.os_type = "Cygwin" then
                Str.global_replace (Str.regexp "\\") "/" file
            else
                file
        in
        let rgb =
            let oimage = OImages.load file [] in
            match OImages.tag oimage with
            | Index8 img ->
                    let rgb = img#to_rgb24 in
                    img#destroy;
                    rgb     
            | Index16 img ->
                    let rgb = img#to_rgb24 in
                    img#destroy;
                    rgb
            | Rgb24 img -> img
            | _ -> raise (Invalid_argument "not supported") 
        in

        let rgb = if !escos_no_ystretch then
            (* halve width *)
            rgb#resize None (rgb#width/2) rgb#height
        else
            rgb
        in

        convert_to_64_colors rgb;

        let rgb = 
            if !mode = Asslace then
                prepare_for_asslace rgb
            else
                rgb
        in
        
        assert (not (!escos && !use_sprites));

        let charwidth = if !escos then 24 else 8
        and charheight = 
            if !custom_char_height != 0 then 
                begin
                    printf "custom char height: %d\n" !custom_char_height;
                    !custom_char_height
                end
            else if !escos then 21 else 8 
        in

        if !mode = Hires & !use_sprites then
            Spriteoverlays.handle_sprite_overlays file rgb !debug charwidth charheight;

        let charlist = get_charlist rgb charwidth charheight in

        let process_charlist = process_charlist !mode !bg !escos !unique_chars
            charwidth charheight !debug
        and bg2 = ref 0 in

        if !interlace then
            begin
                (* interlace *)
                let chars1 = ref []
                and chars2 = ref [] in
                let handle ch =
                    let ch1 = ref []
                    and ch2 = ref [] in
                    let rec split ch =
                        match ch with
                        | [] -> ()
                        | _::[] -> failwith "Error"
                        | p1::p2::tail ->
                                ch1 := !ch1 @ [p1] @ [p1];
                                ch2 := !ch2 @ [p2] @ [p2];
                                split tail
                    in
                    split ch;
                    chars1 := !chars1 @ [!ch1];
                    chars2 := !chars2 @ [!ch2]
                in
                List.iter handle charlist;

                bg := process_charlist !chars1 (file ^ "1");
                bg2 := process_charlist !chars2 (file ^ "2");

                merge_mci_cram file
            end
        else
            bg := process_charlist charlist file;

        if !generate_prg then
            do_generate_prg path file !mode !interlace !bg !bg2 !border !use_sprites; 

    ) files;;

